#!/usr/bin/env python3
"""Strict duplicate-key parse of GitHub workflow and composite-action YAML (Ref #12283, #9927).

WHY. A merge-queue candidate for #12275 carried a ci.yml with two `fetch-depth` keys in one
`with:` mapping. git merged it cleanly; GitHub Actions could not load the file, recorded a failed
`push` run on the queue temp ref, never created the `merge_group` run, and the required `test`
context never reported: a 175-minute stall. PyYAML's default loader (and most "does it parse?"
checks) silently keep the LAST duplicate, so a permissive parse is green on exactly this input.

WHAT. Every `.github/workflows/*.yml|*.yaml` (suffix matched case-insensitively; not recursive,
GitHub loads only the top level) and every `.github/actions/**/action.yml|yaml` under ROOT is
composed into a YAML node graph and walked for repeated mapping keys. Detection runs on the
COMPOSED graph, not during construction, so every real repeat (block or flow mapping, any depth,
any quote style) is collected with its `path:line:col`, and the walk continues so ALL duplicates in
ALL files are reported in one run.

KEY IDENTITY. GitHub compares mapping keys as case-insensitive STRINGS on every mapping, not as
typed YAML values. Source claim, verified 2026-11-07 against actions/runner TemplateReader.cs (the
per-mapping key set is built with StringComparer.OrdinalIgnoreCase, lines 180 and 307 of that
file). So the identity of a scalar key is its source text with ASCII letters folded to upper
case: `Fetch-Depth` and `fetch-depth` collide, `"a"` and `a` collide, `on` and `true` do not
(two different strings to GitHub, although PyYAML's YAML 1.1 resolver reads both as bool), and the merge key `<<` is an ordinary
key (two of them in one mapping are a repeat). The fold is ASCII-only on purpose: Python's full
`upper()` equates sharp-s with `SS` and dotless-i with `i`, which .NET OrdinalIgnoreCase does not.
That text identity is only valid for keys that stay strings. GitHub first converts a PLAIN scalar
key that reads as a YAML 1.2 core null, bool, int or float into a string of its VALUE (`1` and
`1.0` and `0xA`/`10`, `~` and `null` become the same key) and only then runs its duplicate check,
so source text would miss those collisions. The guard does not emulate the conversion (hex, octal
and float-to-string rules could be wrong); instead such a key is itself a finding, is never
compared and never enters the comparison set: `plain scalar key '<k>' is converted to a string by
GitHub before its duplicate check; quote it or rename it`. NON_STRING_PLAIN is the YAML 1.2 core
null/bool/int/float forms only, case-sensitive: `on`, `off`, `yes`, `no`, `y`, `n` are plain
STRINGS in YAML 1.2 (which is why `on:` is safe and not flagged), as are underscore integers and
sexagesimals. The real tree has no such key; a lone numeric key is flagged although GitHub would
accept it (deliberate over-strictness, flip evidence would be a workflow that needs one). A
quoted or block-scalar key is not plain and is compared as text. The style test cannot see an
explicit tag or anchor, so a plain key such as `!!str 5` (a string to GitHub) is flagged too: further
over-strictness with the same remedy, quote it.
Stated residuals, both false-GREEN: non-ASCII case variants that OrdinalIgnoreCase equates are NOT
flagged, and non-scalar (complex) keys are skipped, never compared. Non-scalar keys, unknown tags
and non-plain tagged scalars make GitHub fail to LOAD a file but are outside the duplicate-key
class; the merge-queue stall check covers that failure shape.

FAIL CLOSED. A file that does not parse, holds more than one document, is empty, or whose top
level is not a mapping is a finding, never a skip, and so is an entry named like a workflow that
cannot be opened (a dangling symlink): a guard that skips what it cannot read is the vacuous-green
shape the incident came from. Only directories are skipped.

SCOPE RESIDUALS, stated. Composite actions outside `.github/actions` are not scanned; the suite
carries a tripwire row asserting none is tracked. A symlinked DIRECTORY under `.github/actions` is
not walked (os.walk does not follow it; whether GitHub resolves such a link is unverified). The
host workflow file (pr-quality-guards.yml) is scanned, but a duplicate in it also stops the
`quality-guards` check from reporting, so that case is caught by this script's real-tree row in
the `ci.yml` test gate, not by quality-guards, and the latency differs from the other members: the
red arrives through ci.yml's heavy leg (timeout 60 minutes) in tens of minutes, not minutes. The
residual reopens if ci.yml's gate is narrowed.

USAGE.  python3 check-workflow-duplicate-keys.py [ROOT]
  ROOT defaults to the repository root that contains this script. The summary line is
  `workflow-duplicate-keys=OK files=N loader=c|py pyyaml=V` or
  `workflow-duplicate-keys=FAIL files=N duplicates=D unparseable=U loader=c|py pyyaml=V`; each
  finding is a GitHub annotation `::error file=<rel>,line=<L>,col=<C>::duplicate key '<k>' (first
  at line <F>)` (a plain non-string key prints the message above instead and counts in
  duplicates=). The pyyaml= field is the evidence of which PyYAML the runner image provided.
  Annotation text is escaped for %, CR, LF (GitHub's own set) and, beyond that, U+2028, U+2029,
  U+0085 and DEL are written as \\uXXXX so a key cannot smuggle a line break into the log.

EXIT.  0 clean | 1 any duplicate, unparseable, multi-document, empty or non-mapping file |
       2 environment (PyYAML missing, ROOT not a directory, zero workflow files scanned).
       There is deliberately NO pip fallback: PyYAML is assumed preinstalled on the runner image
       (the pyyaml= field printed by the quality-guards job is the evidence), and a network
       dependency on a required check is worse than a loud exit 2.

LOADER. CSafeLoader when libyaml is available (roughly 0.1-0.7 s over the tree), else the pure
SafeLoader (roughly 1.4-6 s); timings are host dependent. `WFDK_PURE_PYTHON=1` forces the pure loader; it is a TEST-ONLY seam so the suite can run
the same fixtures under both. The summary prints which loader ran. The graph walk here is
iterative; the pure loader's own composer is recursive and can hit its recursion limit on a
pathologically deep document, which fails closed (an unparseable finding, rc 1).
"""
import os
import re
import string
import sys

try:
    import yaml
except Exception:  # noqa: BLE001 -- any import failure is the same environment error
    yaml = None

WF_SUFFIXES = (".yml", ".yaml")
ACTION_NAMES = ("action.yml", "action.yaml")
# ASCII-only upper-case fold (NOT str.upper(): see KEY IDENTITY in the module docstring).
ASCII_FOLD = str.maketrans(string.ascii_lowercase, string.ascii_uppercase)

# Plain scalars GitHub converts to null/bool/number tokens before its duplicate check (YAML 1.2 core
# schema, case-sensitive, matched with fullmatch). The empty alternative is the empty plain key.
# NOT on/off/yes/no/y/n (strings in YAML 1.2), underscore integers or sexagesimals.
NON_STRING_PLAIN = re.compile("|".join((
    "",
    "~|null|Null|NULL",
    "true|True|TRUE|false|False|FALSE",
    "[-+]?[0-9]+",
    "0o[0-7]+",
    "0x[0-9a-fA-F]+",
    r"[-+]?(?:\.[0-9]+|[0-9]+(?:\.[0-9]*)?)(?:[eE][-+]?[0-9]+)?",
    r"[-+]?\.(?:inf|Inf|INF)",
    r"\.(?:nan|NaN|NAN)",
)))
# Control characters left after GitHub's %/CR/LF escaping (CR/LF/tab are handled or harmless): every other
# C0 control, DEL, and the Unicode line separators that Python and other tools treat as line breaks.
CTRL = re.compile("[\x00-\x08\x0b\x0c\x0e-\x1f\x7f\u0085\u2028\u2029]")

LOADER = None


def pick_loader():
    if os.environ.get("WFDK_PURE_PYTHON") == "1":
        return yaml.SafeLoader, "py"
    csafe = getattr(yaml, "CSafeLoader", None)
    if csafe is not None:
        return csafe, "c"
    return yaml.SafeLoader, "py"


def esc_data(s):
    s = CTRL.sub(lambda m: "\\u%04x" % ord(m.group()), str(s))
    return s.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def esc_prop(s):
    return esc_data(s).replace(":", "%3A").replace(",", "%2C")


def emit_error(rel, message, line=None, col=None):
    loc = "file=" + esc_prop(rel)
    if line is not None:
        loc += ",line=%d" % line
        if col is not None:
            loc += ",col=%d" % col
    print("::error %s::%s" % (loc, esc_data(message)))


def check_mapping(node, dups):
    seen = {}
    for key_node, _value_node in node.value:
        if not isinstance(key_node, yaml.ScalarNode):
            continue
        line = key_node.start_mark.line + 1
        col = key_node.start_mark.column + 1
        label = key_node.value
        # style is None (pure loader) or '' (libyaml loader) for a plain scalar.
        if not key_node.style and NON_STRING_PLAIN.fullmatch(label):
            dups.append((line, col, label, None))
            continue
        ident = key_node.value.translate(ASCII_FOLD)
        if ident in seen:
            dups.append((line, col, label, seen[ident]))
        else:
            seen[ident] = line


def collect_duplicates(root, dups):
    """Iterative walk (this loop has no recursion). A visited-id set makes alias cycles terminate
    and reports a node reached through several aliases once."""
    visited = set()
    stack = [root]
    while stack:
        node = stack.pop()
        if id(node) in visited:
            continue
        visited.add(id(node))
        if isinstance(node, yaml.MappingNode):
            check_mapping(node, dups)
            for key_node, value_node in node.value:
                stack.append(key_node)
                stack.append(value_node)
        elif isinstance(node, yaml.SequenceNode):
            stack.extend(node.value)


def load_strict(data, dups):
    node = yaml.compose(data, Loader=LOADER)
    if node is not None:
        collect_duplicates(node, dups)
    return node


def check_file(rel, path):
    """Returns (duplicates, unparseable) for one file; prints one annotation per finding."""
    dups = []
    try:
        with open(path, "rb") as fh:
            data = fh.read()
        node = load_strict(data, dups)
    except Exception as exc:  # noqa: BLE001 -- fail closed: any parse error is a finding
        mark = getattr(exc, "problem_mark", None)
        text = " ".join(str(exc).split())
        if mark is not None:
            emit_error(rel, "unparseable: " + text, mark.line + 1, mark.column + 1)
        else:
            emit_error(rel, "unparseable: " + text)
        return 0, 1  # fail-closed:parse
    if node is None:
        emit_error(rel, "empty file (no YAML document)")
        return 0, 1  # fail-closed:empty
    if not isinstance(node, yaml.MappingNode):
        emit_error(rel, "top level is not a mapping")
        return 0, 1  # fail-closed:non-mapping
    for line, col, label, first in sorted(dups, key=lambda d: (d[0], d[1])):
        if first is None:
            emit_error(rel, "plain scalar key '%s' is converted to a string by GitHub before its "
                       "duplicate check; quote it or rename it" % label, line, col)
        else:
            emit_error(rel, "duplicate key '%s' (first at line %d)" % (label, first), line, col)
    return len(dups), 0


def enumerate_files(root):
    found = []
    wf_dir = os.path.join(root, ".github", "workflows")
    if os.path.isdir(wf_dir):
        for name in sorted(os.listdir(wf_dir)):
            path = os.path.join(wf_dir, name)
            if name.lower().endswith(WF_SUFFIXES) and not os.path.isdir(path):
                found.append(path)
    act_dir = os.path.join(root, ".github", "actions")
    if os.path.isdir(act_dir):
        for dirpath, dirnames, filenames in os.walk(act_dir):
            dirnames.sort()
            for name in sorted(filenames):
                path = os.path.join(dirpath, name)
                if name.lower() in ACTION_NAMES and not os.path.isdir(path):
                    found.append(path)
    return [(os.path.relpath(p, root).replace(os.sep, "/"), p) for p in found]


def env_error(message):
    """Exit-2 paths: a stderr line for humans plus a workflow annotation so the run page names it."""
    print("workflow-duplicate-keys=ERROR " + message, file=sys.stderr)
    print("::error::workflow-duplicate-keys: " + esc_data(message), file=sys.stderr)


def main(argv):
    global LOADER
    # A non-UTF-8 stdout (LANG=C, PYTHONIOENCODING=ascii) must not turn a finding into a traceback.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(errors="replace")
    if yaml is None:
        env_error("PyYAML is not importable (no pip fallback by design)")
        return 2  # env:pyyaml
    if len(argv) > 2:
        print("usage: check-workflow-duplicate-keys.py [ROOT]", file=sys.stderr)
        return 2
    if len(argv) == 2:
        root = os.path.abspath(argv[1])
    else:
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    if not os.path.isdir(root):
        env_error("root %s is not a directory" % root)
        return 2
    LOADER, loader_name = pick_loader()
    files = enumerate_files(root)
    if not files:
        env_error("zero workflow or action files under %s; a scan of nothing is not a pass" % root)
        return 2
    tail = " loader=%s pyyaml=%s" % (loader_name, yaml.__version__)
    duplicates = 0
    unparseable = 0
    for rel, path in files:
        n_dup, n_unp = check_file(rel, path)
        duplicates += n_dup
        unparseable += n_unp
    if duplicates or unparseable:
        print("workflow-duplicate-keys=FAIL files=%d duplicates=%d unparseable=%d%s"
              % (len(files), duplicates, unparseable, tail))
        return 1
    print("workflow-duplicate-keys=OK files=%d%s" % (len(files), tail))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
