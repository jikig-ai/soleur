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
typed YAML values (actions/runner TemplateReader.cs builds an OrdinalIgnoreCase key set for each
mapping it reads). So the identity of a scalar key is its source text with ASCII letters folded to
upper case: `Fetch-Depth` and `fetch-depth` collide, `"a"` and `a` collide, `on` and `true` do not
(two different strings to GitHub, though one bool to YAML), and the merge key `<<` is an ordinary
key (two of them in one mapping are a repeat). The fold is ASCII-only on purpose: Python's full
`upper()` equates sharp-s with `SS` and dotless-i with `i`, which .NET OrdinalIgnoreCase does not.
Stated residuals, both false-GREEN: non-ASCII case variants that OrdinalIgnoreCase equates are NOT
flagged, and non-scalar (complex) keys are skipped, never compared.

FAIL CLOSED. A file that does not parse, holds more than one document, is empty, or whose top
level is not a mapping is a finding, never a skip, and so is an entry named like a workflow that
cannot be opened (a dangling symlink): a guard that skips what it cannot read is the vacuous-green
shape the incident came from. Only directories are skipped.

SCOPE RESIDUALS, stated. Composite actions outside `.github/actions` are not scanned; the suite
carries a tripwire row asserting none is tracked. The host workflow file (pr-quality-guards.yml)
is scanned, but a duplicate in it also stops the `quality-guards` check from reporting, so that
case is caught by this script's real-tree row in the `ci.yml` test gate, not by quality-guards;
the residual reopens if ci.yml's gate is narrowed.

USAGE.  python3 check-workflow-duplicate-keys.py [ROOT]
  ROOT defaults to the repository root that contains this script. The summary line is
  `workflow-duplicate-keys=OK files=N loader=c|py pyyaml=V` or
  `workflow-duplicate-keys=FAIL files=N duplicates=D unparseable=U loader=c|py pyyaml=V`; each
  finding is a GitHub annotation `::error file=<rel>,line=<L>,col=<C>::duplicate key '<k>' (first
  at line <F>)`. The pyyaml= field is the evidence of which PyYAML the runner image provided.

EXIT.  0 clean | 1 any duplicate, unparseable, multi-document, empty or non-mapping file |
       2 environment (PyYAML missing, ROOT not a directory, zero workflow files scanned).
       There is deliberately NO pip fallback: PyYAML is assumed preinstalled on the runner image
       (the pyyaml= field printed by the quality-guards job is the evidence), and a network
       dependency on a required check is worse than a loud exit 2.

LOADER. CSafeLoader when libyaml is available (0.4 s over the tree), else the pure SafeLoader
(5.7 s). `WFDK_PURE_PYTHON=1` forces the pure loader; it is a TEST-ONLY seam so the suite can run
the same fixtures under both. The summary prints which loader ran. The graph walk here is
iterative; the pure loader's own composer is recursive and can hit its recursion limit on a
pathologically deep document, which fails closed (an unparseable finding, rc 1).
"""
import os
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

LOADER = None


def pick_loader():
    if os.environ.get("WFDK_PURE_PYTHON") == "1":
        return yaml.SafeLoader, "py"
    csafe = getattr(yaml, "CSafeLoader", None)
    if csafe is not None:
        return csafe, "c"
    return yaml.SafeLoader, "py"


def esc_data(s):
    return str(s).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


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
        ident = key_node.value.translate(ASCII_FOLD)
        line = key_node.start_mark.line + 1
        col = key_node.start_mark.column + 1
        label = key_node.value
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
