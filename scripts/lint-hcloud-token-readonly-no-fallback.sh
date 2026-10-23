#!/usr/bin/env bash
# Guard 1 (#10664, ADR-241 D4): nothing reads the read/write Hetzner credential through a
# Doppler secrets-get call except the one tracked, expiring `op=backup` read.
#
# This file is the SCANNER (live scan only). Its battery is
# tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh (mutation matrix over synthetic
# fixtures, plus one row that runs this scanner against the real tree and requires findings=0).
#
# xtrace refusal: this script's source names the Doppler read and the credential it forbids, so it
# carries the repo's xtrace refusal ahead of any command (lint-shell-trace-credential-refusal.py).
case "$-" in *x*) printf 'lint-hcloud-token-readonly-no-fallback: refusing to run while xtrace is on\n' >&2; exit 78 ;; esac
#
# OWNER AND TRACKERS. The #9755 work owns the allowlisted entry; trackers #9755 and #10664. The
# reviewer-visible anchor is the ADR-241 2026-10-23 entry (it names the entry, its expiry and its
# trackers). Renewal is a dated edit of ALLOW_EXPIRY below with a stated reason in that entry;
# deletion of the entry (together with the `op=backup` read) is the intended end.
#
# PROPERTY. No file in the scanned population reads the read/write Hetzner credential through
# `doppler secrets get` by (F-literal) the word-bounded bare name HCLOUD_TOKEN as any operand,
# (F-sameline) a non-literal operand on a logical line that also names a word-bounded HCLOUD_TOKEN
# or HCLOUD_TOKEN_READONLY, or (F-onehop) a "$v" / "${v}" operand whose same-file definition site
# holds a word-bounded bare HCLOUD_TOKEN. Definition sites (closed list): `v=` (also `local v=`,
# `declare -n v=`, an array literal `v=(...)`), `${v:-...}`, `for v in`, `read ... v` (including a
# here-string) and `printf -v v`. HCLOUD_TOKEN is a prefix of HCLOUD_TOKEN_READONLY, so every
# pattern is word-bounded. The parser does NOT distinguish command position: a bare read inside an
# echo or printf string is a printed recipe the next agent pastes, so it is a finding (rephrase the
# text or allowlist it).
#
# PARSER. Backslash continuations are joined; whole-line comments are dropped (and counted);
# `doppler` global options are allowed before `secrets`; flags are tolerated between `secrets` and
# `get`; EVERY non-option operand after `get` is a name, skipping the values of -p, -c, --project,
# --config, --token, --timeout, --config-dir, --api-host, --scope and --log-level; quotes are
# stripped; the operand list ends at a shell operator (| ; & ( ) ` or a redirect).
#
# POPULATION. `git ls-files -z --cached --others --exclude-standard` under the root MINUS a pinned
# exclusion list: tests (a directory segment in {test, tests, __tests__, fixtures}, a `.test.` /
# `.spec.` infix, a `.tftest.hcl` suffix, a `test-*` basename), knowledge-base/, docs (a `docs`
# directory segment), *.md / *.mdx, lockfiles, generated JSON (*.likec4.json, package-lock.json),
# symlinks, .github/workflows/** (the Tier-B census owns the workflows) and this scanner and its
# suite. Inverting the selection (everything except the list) is what brings `.claude/hooks`,
# `*.service`, cloud-init*.yml and *.tf into scope. A tracked path that is a directory, a dangling
# symlink or unreadable is FAIL SETUP (rc 2), never "no findings"; a tracked path deleted from the
# disk is skipped.
#
# ALLOWLIST. Keyed on (file, whitespace-normalized logical line text, exact count) with an expiry:
# exactly one entry, the `op=backup` read in scripts/cutover-inngest.sh (#9755, #10664). The entry
# must match EXACTLY its count (0 = stale and RED, 2 = a re-added copy and RED). A failure prints
# the expected and the found text.
#
# LIVENESS FLOORS (never satisfied by an empty scan). At least 20 reads inspected, and the
# allowlisted line found exactly once.
#
# NAMED BLIND SPOTS. This is a text guard; it does not see: a name that arrives from env or argv at
# runtime; a chain of two or more assignments; wrapper-function indirection (a helper taking the
# name as an argument; parsing a wrapper body needs call-graph work that false-positives on
# `_bearer_curl HCLOUD_TOKEN`, and the runtime backstop is real: the bare name is absent from
# prd_terraform, so such a read returns empty and fails closed); a name assembled from separate
# variables; a definition of the indirect variable in ANOTHER file; `doppler run -- printenv`,
# `--only-secrets` and `secrets download`; a Doppler call whose program name is not the literal word
# `doppler`; and reads that are not secrets-get calls (the loader-delivered `rw) _var=HCLOUD_TOKEN`
# in apps/web-platform/infra/git-data-wipe.sh). It also cannot tell that a read/write token was
# stored UNDER the read-only name; that control stays the O5 write-probe of
# knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md.
# The Phase 0.1.2 live run found no hit from F-sameline or F-onehop on an unrelated site, so both
# non-literal arms are kept.
#
# SEAMS. HCLOUD_SCAN_ROOT (the tree; default the repo root) and HCLOUD_SCAN_TODAY (strict
# YYYY-MM-DD and a real calendar date, else FAIL SETUP; default `date -u +%F`; a visible line is
# printed whenever either is set). When GITHUB_ACTIONS is set and either variable is inherited the
# scanner exits FAIL SETUP (rc 2): the clock and root seams cannot be set from a workflow's
# environment. Options: --event-name NAME (default GITHUB_EVENT_NAME; "" is a local run),
# --changed-files FILE (newline list of changed paths; default: git diff against the merge-base
# with refs/remotes/origin/main, an unresolved base counts as touching), --emit-candidates FILE
# (NUL-separated scanned paths that mention doppler, for the suite's population-copy row).
#
# EXPIRY (ceiling 2026-12-15, the trio model of test-trio-baseline-census.sh). Within 21 days
# before the expiry (and on the expiry day) a ::warning:: is printed on every event and the exit is
# unchanged. Past the expiry the scanner is RED (F-expired) ONLY on a pull_request event whose diff
# touches scripts/cutover-inngest.sh, this scanner, the suite or ADR-241; on push, merge_group,
# schedule and local runs it prints a ::warning:: and the exit is unchanged, so the expiry can never
# stop an unrelated PR or a tenant deploy through ci_not_green.
#
# OUTPUT. FINDING lines, a `counters:` line, then `live: findings=N allowlisted=M`.
# EXIT. 0 clean; 1 findings; 2 FAIL SETUP (cannot enumerate or read the population); 64 bad call;
# 78 xtrace on.
set -uo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
event_name="${GITHUB_EVENT_NAME-}"
changed_files=""
emit_candidates=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --event-name) [ "$#" -ge 2 ] || { echo "usage: --event-name NAME" >&2; exit 64; }; event_name="$2"; shift 2 ;;
    --changed-files) [ "$#" -ge 2 ] || { echo "usage: --changed-files FILE" >&2; exit 64; }; changed_files="$2"; shift 2 ;;
    --emit-candidates) [ "$#" -ge 2 ] || { echo "usage: --emit-candidates FILE" >&2; exit 64; }; emit_candidates="$2"; shift 2 ;;
    *) echo "usage: lint-hcloud-token-readonly-no-fallback.sh [--event-name N] [--changed-files F] [--emit-candidates F]" >&2; exit 64 ;;
  esac
done

if [ -n "${GITHUB_ACTIONS-}" ] && { [ -n "${HCLOUD_SCAN_ROOT+x}" ] || [ -n "${HCLOUD_SCAN_TODAY+x}" ]; }; then
  echo "FAIL SETUP: GITHUB_ACTIONS is set and HCLOUD_SCAN_ROOT/HCLOUD_SCAN_TODAY is inherited; the clock and root seams cannot be set from a workflow environment" >&2
  exit 2
fi

root="${HCLOUD_SCAN_ROOT-$(cd -P "$HERE/.." && pwd -P)}"
if [ -n "${HCLOUD_SCAN_ROOT+x}" ]; then
  printf 'scan: HCLOUD_SCAN_ROOT override active: %s\n' "$HCLOUD_SCAN_ROOT"
fi
case "$root" in
  /?*) : ;;
  *) echo "FAIL SETUP: scan root is empty or not absolute: $root" >&2; exit 2 ;;
esac
[ -d "$root" ] || { echo "FAIL SETUP: scan root is not a directory: $root" >&2; exit 2; }

if [ -n "${HCLOUD_SCAN_TODAY+x}" ]; then
  today="$HCLOUD_SCAN_TODAY"
  printf 'scan: HCLOUD_SCAN_TODAY override active: %s\n' "$HCLOUD_SCAN_TODAY"
else
  today="$(date -u +%F)"
fi

exec python3 -I - "$root" "$today" "$event_name" "$changed_files" "$emit_candidates" <<'PY'
import datetime
import os
import re
import stat
import subprocess
import sys

root, today_s, event_name, changed_arg, emit_path = sys.argv[1:6]

NAME_BARE = "HCLOUD_" + "TOKEN"
NAME_RO = NAME_BARE + "_READONLY"
BARE_RE = re.compile(r"(?<![A-Za-z0-9_])" + NAME_BARE + r"(?![A-Za-z0-9_])")
SAMELINE_RE = re.compile(r"(?<![A-Za-z0-9_])" + NAME_BARE + r"(?:_READONLY)?(?![A-Za-z0-9_])")

# The allowlist: (file, whitespace-normalized logical line text, exact count). The text is built from
# parts so this file never carries the read it permits as one searchable string.
ALLOW_FILE = "scripts/cutover-inngest.sh"
ALLOW_TEXT = NAME_BARE + "=$(" + "dopp" + "ler secrets get " + NAME_BARE + " --plain)"
ALLOW_COUNT = 1
ALLOW_EXPIRY = datetime.date(2026, 12, 15)
WARN_DAYS = 21
MIN_INSPECTED = 20

SELF_PATHS = {
    "scripts/lint-hcloud-token-readonly-no-fallback.sh",
    "tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh",
}
GUARDED = SELF_PATHS | {
    "scripts/cutover-inngest.sh",
    "knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md",
}


def setup_fail(msg):
    sys.stderr.write("FAIL SETUP: %s\n" % msg)
    sys.exit(2)


# ---- the clock ------------------------------------------------------------------------------
if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", today_s):
    setup_fail("HCLOUD_SCAN_TODAY must be YYYY-MM-DD, got %r" % today_s)
try:
    TODAY = datetime.date.fromisoformat(today_s)
except ValueError:
    setup_fail("HCLOUD_SCAN_TODAY is not a real calendar date: %r" % today_s)

# ---- enumeration ----------------------------------------------------------------------------
GIT_DROP = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY",
            "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE", "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS")
genv = {k: v for k, v in os.environ.items() if k not in GIT_DROP}


def git(*args):
    try:
        return subprocess.run(["git", "-C", root] + list(args), env=genv, capture_output=True)
    except OSError as e:
        setup_fail("cannot run git: %s" % e)


top = git("rev-parse", "--show-toplevel")
if top.returncode != 0:
    setup_fail("root %s is not a git work tree: %s" % (root, top.stderr.decode("utf-8", "replace").strip()[:200]))
if os.path.realpath(top.stdout.decode("utf-8", "replace").strip()) != os.path.realpath(root):
    setup_fail("root %s is not the top of a git work tree" % root)
ls = git("ls-files", "-z", "--cached", "--others", "--exclude-standard")
if ls.returncode != 0:
    setup_fail("git ls-files failed: %s" % ls.stderr.decode("utf-8", "replace").strip()[:200])
paths = sorted(set(os.fsdecode(p) for p in ls.stdout.split(b"\0") if p))

# ---- population classes ---------------------------------------------------------------------
TEST_DIRS = {"test", "tests", "__tests__", "fixtures"}
LOCK_NAMES = {"package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock", "bun.lockb", "uv.lock",
              "Cargo.lock", "Gemfile.lock", "poetry.lock", ".terraform.lock.hcl", "composer.lock"}


def klass(rel):
    """None = scanned; 'silent' = excluded without a count; 'test' = excluded test class (reads counted)."""
    if rel in SELF_PATHS:
        return "silent"
    segs = rel.split("/")
    base = segs[-1]
    if rel.startswith("knowledge-base/") or rel.startswith(".github/workflows/"):
        return "silent"
    if "docs" in segs[:-1]:
        return "silent"
    if base.endswith((".md", ".mdx", ".markdown", ".lock")) or base in LOCK_NAMES or base.endswith(".likec4.json"):
        return "silent"
    if any(s in TEST_DIRS for s in segs[:-1]):
        return "test"
    if re.search(r"\.(?:test|spec)\.[^/]+$", base) or base.endswith(".tftest.hcl") or base.startswith("test-"):
        return "test"
    return None


# ---- the read parser ------------------------------------------------------------------------
VALUE_OPTS = {"-p", "-c", "--project", "--config", "--token", "--timeout", "--config-dir", "--api-host",
              "--scope", "--log-level"}
DOPPLER_RE = re.compile(r"(?<![A-Za-z0-9_.\-])dopp" + r"ler(?![A-Za-z0-9_\-])")
TOK_RE = re.compile(
    r"""\s+
      |(?P<op>\d*(?:<<<|<<-?|>>|>&|<&|>\||>|<)|&&|\|\||[|;&()`])
      |(?P<word>(?:'[^']*'|"(?:\\.|[^"\\])*"|[^\s|;&()<>'"`])+)
      |(?P<stray>['"])""",
    re.X | re.S,
)


def word_text(w):
    out = []
    for m in re.finditer(r"""'([^']*)'|"((?:\\.|[^"\\])*)"|([^'"]+)""", w):
        out.append(m.group(1) if m.group(1) is not None else (m.group(2) if m.group(2) is not None else m.group(3)))
    t = "".join(out)
    return t.rstrip("\\.,:;")


def quote_state(prefix):
    """Quote context at the end of prefix: 'dq', 'sq' or '' (command position)."""
    stack = ["cmd"]
    i, n = 0, len(prefix)
    while i < n:
        c = prefix[i]
        top = stack[-1]
        if top == "sq":
            if c == "'":
                stack.pop()
        elif top == "dq":
            if c == "\\":
                i += 1
            elif c == '"':
                stack.pop()
            elif c == "$" and prefix[i + 1:i + 2] == "(":
                stack.append("sub")
                i += 1
        else:
            if c == "\\":
                i += 1
            elif c == "'":
                stack.append("sq")
            elif c == '"':
                stack.append("dq")
            elif c == "$" and prefix[i + 1:i + 2] == "(":
                stack.append("sub")
                i += 1
            elif c == "(":
                stack.append("paren")
            elif c == ")" and top in ("sub", "paren"):
                stack.pop()
        i += 1
    return stack[-1] if stack[-1] in ("dq", "sq") else ""


def tokenize(s):
    toks = []
    for m in TOK_RE.finditer(s):
        if m.lastgroup == "op":
            toks.append(("op", m.group("op")))
        elif m.lastgroup == "word":
            toks.append(("word", m.group("word")))
    return toks


def find_reads(logical):
    """Yield operand lists, one per secrets-get read in the logical line."""
    if "dopp" + "ler" not in logical:
        return
    for m in DOPPLER_RE.finditer(logical):
        rest = logical[m.start():]
        qs = quote_state(logical[:m.start()])
        if qs == "dq":
            cut = re.search(r'(?<!\\)"', rest)
            rest = rest[:cut.start()] if cut else rest
        elif qs == "sq":
            cut = rest.find("'")
            rest = rest[:cut] if cut >= 0 else rest
        toks = tokenize(rest)
        if not toks or toks[0][0] != "word" or word_text(toks[0][1]) != "dopp" + "ler":
            continue
        j, n = 1, len(toks)
        ok = False
        while j < n:
            kind, w = toks[j]
            if kind != "word":
                break
            t = word_text(w)
            if t == "secrets":
                ok = True
                j += 1
                break
            if not t.startswith("-"):
                break
            j += 2 if t in VALUE_OPTS else 1
        if not ok:
            continue
        got = False
        while j < n:
            kind, w = toks[j]
            if kind != "word":
                break
            t = word_text(w)
            if t == "get":
                got = True
                j += 1
                break
            if not t.startswith("-"):
                break
            j += 2 if t in VALUE_OPTS else 1
        if not got:
            continue
        operands = []
        while j < n:
            kind, w = toks[j]
            if kind != "word":
                break
            t = word_text(w)
            if t.startswith("-") and t != "-":
                j += 2 if t in VALUE_OPTS else 1
                continue
            if t:
                operands.append(t)
            j += 1
        yield operands


def logical_lines(text):
    """(start_line_no, logical_text, is_comment) with backslash continuations joined."""
    lines = text.split("\n")
    out = []
    i, n = 0, len(lines)
    while i < n:
        line = lines[i]
        if line.lstrip().startswith("#"):
            out.append((i + 1, line, True))
            i += 1
            continue
        start = i + 1
        cur = line
        while cur.endswith("\\"):
            m = re.search(r"(\\+)$", cur)
            if m and len(m.group(1)) % 2 == 1 and i + 1 < n:
                cur = cur[:-1] + " " + lines[i + 1].lstrip()
                i += 1
            else:
                break
        out.append((start, cur, False))
        i += 1
    return out


def norm(s):
    return " ".join(s.split())


def defines_bare(v, lines):
    ve = re.escape(v)
    pats_rest = [
        re.compile(r"(?<![A-Za-z0-9_$])" + ve + r"\+?="),
        re.compile(r"\$\{" + ve + r":?[-=+?]"),
        re.compile(r"\bfor\s+" + ve + r"\s+in\b"),
    ]
    read_pat = re.compile(r"\bread\b[^;&|]*?(?<![A-Za-z0-9_$])" + ve + r"(?![A-Za-z0-9_])")
    printf_pat = re.compile(r"\bprintf\s+-v\s+" + ve + r"(?![A-Za-z0-9_])")
    for _no, lt, is_c in lines:
        if is_c:
            continue
        for p in pats_rest:
            for m in p.finditer(lt):
                seg = re.split(r";|&&|\|\|", lt[m.end():], maxsplit=1)[0]
                if BARE_RE.search(seg):
                    return True
        if (read_pat.search(lt) or printf_pat.search(lt)) and BARE_RE.search(lt):
            return True
    return False


# ---- scan -----------------------------------------------------------------------------------
findings = []
c = dict(files=0, inspected=0, operands=0, nonliteral=0, skipped_comment=0, skipped_test=0,
         skipped_symlink=0, skipped_binary=0, skipped_deleted=0)
allow_hits = 0
candidates = []
allow_found_texts = []

for rel in paths:
    kl = klass(rel)
    if kl == "silent":
        continue
    full = os.path.join(root, rel)
    try:
        st = os.lstat(full)
    except FileNotFoundError:
        c["skipped_deleted"] += 1
        continue
    except OSError as e:
        setup_fail("cannot stat %s: %s" % (rel, e))
    if stat.S_ISLNK(st.st_mode):
        if not os.path.exists(full):
            setup_fail("population path %s is a dangling symlink" % rel)
        c["skipped_symlink"] += 1
        continue
    if stat.S_ISDIR(st.st_mode):
        setup_fail("population path %s is a directory (a tracked file was replaced or a submodule is present)" % rel)
    if not stat.S_ISREG(st.st_mode):
        setup_fail("population path %s is not a regular file" % rel)
    try:
        with open(full, "rb") as fh:
            data = fh.read()
    except OSError as e:
        setup_fail("cannot read %s: %s" % (rel, e))
    if b"\0" in data[:8192]:
        c["skipped_binary"] += 1
        continue
    if kl is None:
        c["files"] += 1
    if b"dopp" + b"ler" not in data:
        continue
    text = data.decode("utf-8", "replace")
    lines = logical_lines(text)
    if kl == "test":
        for _no, lt, _ic in lines:
            for _ops in find_reads(lt.lstrip("# \t") if _ic else lt):
                c["skipped_test"] += 1
        continue
    candidates.append(rel)
    for no, lt, is_c in lines:
        if is_c:
            for _ops in find_reads(lt.lstrip("# \t")):
                c["skipped_comment"] += 1
            continue
        for operands in find_reads(lt):
            c["inspected"] += 1
            nl = norm(lt)
            for name in operands:
                c["operands"] += 1
                if re.fullmatch(NAME_BARE, name):
                    if rel == ALLOW_FILE and nl == ALLOW_TEXT:
                        allow_hits += 1
                    else:
                        findings.append("FINDING F-literal %s:%d: %s" % (rel, no, nl))
                    continue
                if "$" not in name:
                    continue
                c["nonliteral"] += 1
                if SAMELINE_RE.search(lt):
                    findings.append("FINDING F-sameline %s:%d: %s" % (rel, no, nl))
                    continue
                hop = re.fullmatch(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?", name)
                if hop and defines_bare(hop.group(1), lines):
                    findings.append("FINDING F-onehop %s:%d: %s (variable %s is defined from the bare name)"
                                    % (rel, no, nl, hop.group(1)))

# ---- allowlist, floors, expiry ---------------------------------------------------------------
if allow_hits != ALLOW_COUNT:
    findings.append("FINDING F-allowlist %s: expected the line %r exactly %d time(s), found %d"
                    % (ALLOW_FILE, ALLOW_TEXT, ALLOW_COUNT, allow_hits))
if c["inspected"] < MIN_INSPECTED:
    findings.append("FINDING F-floor: inspected %d reads, floor is %d (an empty or shrunken population is not a clean scan)"
                    % (c["inspected"], MIN_INSPECTED))

anns = []
days_left = (ALLOW_EXPIRY - TODAY).days
if days_left < 0:
    touched = None
    blocking = event_name == "pull_request"
    if blocking:
        if changed_arg:
            try:
                with open(changed_arg, "r", encoding="utf-8") as fh:
                    changed = {l.strip() for l in fh if l.strip()}
            except OSError as e:
                setup_fail("cannot read --changed-files %s: %s" % (changed_arg, e))
            touched = bool(changed & GUARDED)
        else:
            touched = True
            mb = git("merge-base", "HEAD", "refs/remotes/origin/main")
            if mb.returncode == 0 and mb.stdout.strip():
                df = git("diff", "--name-only", "-z", mb.stdout.decode().strip())
                un = git("ls-files", "-z", "--others", "--exclude-standard")
                if df.returncode == 0 and un.returncode == 0:
                    changed = {os.fsdecode(p) for p in (df.stdout + b"\0" + un.stdout).split(b"\0") if p}
                    touched = bool(changed & GUARDED)
    if blocking and touched:
        findings.append("FINDING F-expired: the allowlist entry for %s expired %s (today %s) and this pull_request touches a guarded file; "
                        "delete the entry together with the op=backup read, or renew ALLOW_EXPIRY with a stated reason in the ADR-241 2026-10-23 entry (#9755, #10664)"
                        % (ALLOW_FILE, ALLOW_EXPIRY.isoformat(), TODAY.isoformat()))
    else:
        anns.append("::warning::hcloud-token-readonly-no-fallback: the allowlist entry for %s expired %s (today %s); non-blocking on event %r%s. "
                    "Delete the entry with the op=backup read, or renew it with a stated reason (#9755, #10664)"
                    % (ALLOW_FILE, ALLOW_EXPIRY.isoformat(), TODAY.isoformat(), event_name or "local",
                       "" if not blocking else " (this change touches no guarded file)"))
elif days_left <= WARN_DAYS:
    anns.append("::warning::hcloud-token-readonly-no-fallback: the allowlist entry for %s expires %s (%d day(s) left); delete it with the op=backup read or renew it with a stated reason (#9755, #10664)"
                % (ALLOW_FILE, ALLOW_EXPIRY.isoformat(), days_left))

if emit_path:
    try:
        with open(emit_path, "wb") as fh:
            fh.write(b"".join(os.fsencode(p) + b"\0" for p in candidates))
    except OSError as e:
        setup_fail("cannot write --emit-candidates %s: %s" % (emit_path, e))

for a in anns:
    print(a)
for f in findings:
    print(f)
print("counters: files=%d inspected=%d operands=%d nonliteral=%d skipped_comment=%d skipped_test=%d skipped_symlink=%d skipped_binary=%d skipped_deleted=%d"
      % (c["files"], c["inspected"], c["operands"], c["nonliteral"], c["skipped_comment"], c["skipped_test"],
         c["skipped_symlink"], c["skipped_binary"], c["skipped_deleted"]))
print("live: findings=%d allowlisted=%d" % (len(findings), allow_hits))
sys.exit(1 if findings else 0)
PY
