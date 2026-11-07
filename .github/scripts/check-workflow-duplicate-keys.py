#!/usr/bin/env python3
"""Strict duplicate-key parse of GitHub workflow and composite-action YAML (Ref #12283, #9927).

WHY. A merge-queue candidate for #12275 carried a ci.yml with two `fetch-depth` keys in one
`with:` mapping. git merged it cleanly; GitHub Actions could not load the file, recorded a failed
`push` run on the queue temp ref, never created the `merge_group` run, and the required `test`
context never reported: a 175-minute stall. PyYAML's default loader (and most "does it parse?"
checks) silently keep the LAST duplicate, so a permissive parse is green on exactly this input.

WHAT. Every `.github/workflows/*.yml|*.yaml` and every `.github/actions/**/action.yml|yaml`
under ROOT is composed into a YAML node graph and walked for repeated mapping keys. Detection runs
on the COMPOSED graph, not during construction: a `construct_mapping` override sees mappings after
merge-key flattening, which can fake a duplicate. Here `<<` merge entries are skipped, so a merge
with an explicit override is fine, while every real repeat (block or flow mapping, any depth, any
quote style) is collected with its `path:line:col`, and the walk continues so ALL duplicates in ALL
files are reported in one run.

FAIL CLOSED. A file that does not parse, holds more than one document, is empty, or whose top
level is not a mapping is a finding, never a skip: a guard that skips what it cannot read is the
vacuous-green shape the incident came from.

USAGE.  python3 check-workflow-duplicate-keys.py [ROOT]
  ROOT defaults to the repository root that contains this script. The summary line is
  `workflow-duplicate-keys=OK files=N loader=c|py` or
  `workflow-duplicate-keys=FAIL files=N duplicates=D unparseable=U loader=c|py`; each finding is a
  GitHub annotation `::error file=<rel>,line=<L>,col=<C>::duplicate key '<k>' (first at line <F>)`.

EXIT.  0 clean | 1 any duplicate, unparseable, multi-document, empty or non-mapping file |
       2 environment (PyYAML missing, ROOT not a directory, zero workflow files scanned).
       There is deliberately NO pip fallback: PyYAML is preinstalled on the runner image, and a
       network dependency on a required check is worse than a loud exit 2.

LOADER. CSafeLoader when libyaml is available (0.4 s over the tree), else the pure SafeLoader
(5.7 s). `WFDK_PURE_PYTHON=1` forces the pure loader; it is a TEST-ONLY seam so the suite can run
the same fixtures under both. The summary prints which loader ran.

NOT A SCHEMA VALIDATOR: unknown keys and bad expressions are actionlint's job (advisory). Residual,
stated: GitHub treats `with:`/`env:` input names case-insensitively, so `Fetch-Depth` plus
`fetch-depth` passes this guard.
"""
import os
import sys

try:
    import yaml
except Exception:  # noqa: BLE001 -- any import failure is the same environment error
    yaml = None

WF_SUFFIXES = (".yml", ".yaml")
ACTION_NAMES = ("action.yml", "action.yaml")
MERGE_TAG = "tag:yaml.org,2002:merge"
STR_TAG = "tag:yaml.org,2002:str"

LOADER = None
_CONSTRUCTOR = None


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


def key_identity(key_node):
    """Identity of a scalar key: constructed value plus its type, so `1` and `true` differ while
    `on` and `true` (both bool True, which is how PyYAML loads them) and `"a"` / `a` collide."""
    global _CONSTRUCTOR
    if key_node.tag == STR_TAG:
        return ("str", key_node.value)
    try:
        if _CONSTRUCTOR is None:
            _CONSTRUCTOR = yaml.SafeLoader("")
        val = _CONSTRUCTOR.construct_object(key_node, deep=True)
        hash(val)
        return (type(val).__name__, val)
    except Exception:  # noqa: BLE001 -- unknown tag / unhashable: fall back to the source text
        return (key_node.tag, key_node.value)


def check_mapping(node, dups):
    seen = {}
    for key_node, _value_node in node.value:
        if not isinstance(key_node, yaml.ScalarNode):
            continue
        if key_node.tag == MERGE_TAG:
            continue
        ident = key_identity(key_node)
        line = key_node.start_mark.line + 1
        col = key_node.start_mark.column + 1
        label = key_node.value
        if ident in seen:
            dups.append((line, col, label, seen[ident]))
        else:
            seen[ident] = line


def collect_duplicates(root, dups):
    """Iterative walk (deep documents cannot hit the recursion limit). A visited-id set makes alias
    cycles terminate and reports a node reached through several aliases once."""
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
            if name.endswith(WF_SUFFIXES) and os.path.isfile(path):
                found.append(path)
    act_dir = os.path.join(root, ".github", "actions")
    if os.path.isdir(act_dir):
        for dirpath, dirnames, filenames in os.walk(act_dir):
            dirnames.sort()
            for name in sorted(filenames):
                path = os.path.join(dirpath, name)
                if name in ACTION_NAMES and os.path.isfile(path):
                    found.append(path)
    return [(os.path.relpath(p, root).replace(os.sep, "/"), p) for p in found]


def main(argv):
    global LOADER
    if yaml is None:
        print("workflow-duplicate-keys=ERROR PyYAML is not importable (no pip fallback by design)",
              file=sys.stderr)
        return 2  # env:pyyaml
    if len(argv) > 2:
        print("usage: check-workflow-duplicate-keys.py [ROOT]", file=sys.stderr)
        return 2
    if len(argv) == 2:
        root = os.path.abspath(argv[1])
    else:
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    if not os.path.isdir(root):
        print("workflow-duplicate-keys=ERROR root %s is not a directory" % root, file=sys.stderr)
        return 2
    LOADER, loader_name = pick_loader()
    files = enumerate_files(root)
    if not files:
        print("workflow-duplicate-keys=ERROR zero workflow or action files under %s; a scan of "
              "nothing is not a pass" % root, file=sys.stderr)
        return 2
    duplicates = 0
    unparseable = 0
    for rel, path in files:
        n_dup, n_unp = check_file(rel, path)
        duplicates += n_dup
        unparseable += n_unp
    if duplicates or unparseable:
        print("workflow-duplicate-keys=FAIL files=%d duplicates=%d unparseable=%d loader=%s"
              % (len(files), duplicates, unparseable, loader_name))
        return 1
    print("workflow-duplicate-keys=OK files=%d loader=%s" % (len(files), loader_name))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
