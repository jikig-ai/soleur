"""Shared corpus scanner for the two fixture-safety guards (#7652).

WHY ONE MODULE AND NOT TWO COPIES. `fixture-cd-containment.test.sh` forbids the shape where a
failed `cd` redirects a git write into the caller's repository. Its sibling forbids the shape where
an EMPTY `-C` operand does the same thing without any `cd` at all. The two rules are different; the
machinery underneath them — which files are in the corpus, which lines are heredoc BODY rather than
code, which lines are comments, whether a `set -e` is in scope — is identical, and a comment in one
file asking the reader to keep it in step with another file is not an invariant. Sharing the module
is what makes the composition checkable instead of aspirational.

THE TWO RULES

`scan_cd` — the 2026-08-20 shape:

    (                      # no `set -e` in scope
      cd "$FIXTURE"        # failure does not abort...
      git commit -m x      # ...so this runs wherever the shell happens to be
    )

`scan_operand` — the P1a shape, which no `cd` guard can see because no `cd` is involved:

    helper() {
      local dir="$1"                       # nothing asserts this is non-empty
      git -C "$dir" config commit.gpgsign false
    }
    helper ""                              # -> writes into the CALLER's repository

`git -C ""` does not error. It silently operates on the current directory:

    $ d=$(mktemp -d); cd "$d" && git init -q .
    $ git -C "" config user.name probe-value   # rc=0
    $ git -C "$d" config --get user.name       # -> probe-value

`init` is in the write-verb list deliberately. The intuition "re-initialising an existing repo is
harmless" is wrong and would otherwise cull it: `git -C "" init` returns 0 and reinitialises the
caller's repository.

SCOPE. `scan_operand` covers P1a — the EMPTY operand — only. P1b (a RELATIVE operand, and the
`rm -rf ""` / `mv a ""` / redirection families) is tracked separately, because the verbs do not
share a failure mode: measured, only `git -C` WIDENS on an empty operand, `rm -rf ""` is a silent
no-op and `mv a ""` errors. Stating that is the point — a silent omission would read as coverage.
"""

import os
import re
import subprocess
import sys

# --- shared lexical machinery -------------------------------------------------------------------

SET_E = re.compile(r'^\s*set\s+-[a-zA-Z]*e')
HEREDOC = re.compile(r'<<-?\s*[\'"]?([A-Za-z_][A-Za-z0-9_]*)[\'"]?')


def heredoc_lines(lines):
    """Line indices inside a heredoc BODY.

    Suites here routinely EMBED fixture scripts in heredocs, including fixtures that deliberately
    spell the forbidden shape so a scanner can be proven non-vacuous. Those bodies are data, not
    code that will run in this shell — treating them as code makes every such suite a false
    positive, starting with the scanners themselves.
    """
    inside, term, out = False, None, set()
    for i, l in enumerate(lines):
        if inside:
            out.add(i)
            if l.strip() == term:
                inside, term = False, None
            continue
        m = HEREDOC.search(l)
        if m and not l.lstrip().startswith("#"):
            inside, term = True, m.group(1)
    return out


def scope_has_set_e(lines, idx):
    """`set -e` at file level, or inside the subshell enclosing `idx`."""
    for l in lines[:idx]:
        if SET_E.match(l) and not l.lstrip().startswith("#"):
            if l == l.lstrip():          # column 0 => file-level, covers everything below
                return True
    depth = 0
    for j in range(idx - 1, max(-1, idx - 60), -1):
        s = lines[j].strip()
        if s.startswith("#"):
            continue
        if s == ")":
            depth += 1
        elif s == "(" or s.endswith("("):
            if depth == 0:
                for k in range(j + 1, idx):
                    if SET_E.match(lines[k]) and not lines[k].lstrip().startswith("#"):
                        return True
                return False
            depth -= 1
    return False


def read_lines(path):
    try:
        return open(path, encoding="utf-8", errors="replace").read().split("\n")
    except OSError:
        return None


def tracked_shell_files(repo_root, pattern="*.sh"):
    """The corpus.

    `*.sh`, not `*.test.sh`. The narrower suffix misses `tests/hooks/test_hook_emissions.sh` (a
    `git -C "$path" init` helper the runner DOES run), `.github/scripts/test/test-*.sh`, sourced
    libraries such as `plugins/soleur/test/test-helpers.sh`, and standalone gate scripts. A corpus
    that excludes the files where the helpers actually live is a declaration site.
    """
    r = subprocess.run(["git", "-C", repo_root, "ls-files", pattern],
                       capture_output=True, text=True)
    return [os.path.join(repo_root, p) for p in r.stdout.split()]


# --- rule 1: a failed `cd` redirects a git write --------------------------------------------------

CD_WRITE = re.compile(
    r'\bgit\s+(?:-c\s+\S+\s+)*'
    r'(commit|push|add\b|update-ref|checkout|reset|branch\s+-[dD]|worktree\s+(add|remove)'
    r'|rm\b|mv\b|config)'
)
CD = re.compile(r'^(\s*)\(?\s*cd\s+["\']?\$')


def scan_cd(paths):
    out = []
    for f in paths:
        lines = read_lines(f)
        if lines is None:
            continue
        skip = heredoc_lines(lines)
        for i, line in enumerate(lines):
            if i in skip or line.lstrip().startswith("#"):
                continue
            if not CD.match(line):
                continue
            if "&&" in line or "||" in line or "cdx" in line:
                continue                      # self-guarding
            if scope_has_set_e(lines, i):
                continue                      # a failed cd aborts
            for off, wl in enumerate(lines[i + 1:i + 13]):
                if (i + 1 + off) in skip or wl.lstrip().startswith("#"):
                    continue
                m = CD_WRITE.search(wl)
                if not m:
                    continue
                if "git -C" in wl:
                    continue                  # names its own repo; a lost cwd is inert
                out.append((f, i + 1, line.strip()[:58], i + 2 + off, m.group(0)[:30]))
                break
    return out


# --- rule 2 (P1a): an empty `-C` operand retargets a git write ------------------------------------

# `config` and `init` are load-bearing members. `config` is the verb that produced the 2026-08-20
# incident; `init` returns 0 and reinitialises the caller's repository, which "re-init is harmless"
# would otherwise cull.
OPERAND_WRITE = re.compile(
    r'\bgit\s+-C\s+"\$\{?(?P<var>[A-Za-z_][A-Za-z0-9_]*|[0-9]+)\}?"\s+'
    r'(?:-c\s+\S+\s+)*'
    r'(?P<verb>commit|push|add\b|update-ref|checkout|reset|branch|worktree\s+add|worktree\s+remove'
    r'|rm\b|mv\b|config|init|clone|tag|fetch|apply|stash|gc|prune|symbolic-ref)\b'
)

# Bindings that can carry an empty value. A literal (`d="/tmp/x"`) cannot, and is not a candidate.
#
# These are built PER VARIABLE at match time rather than as line-anchored patterns. The
# line-anchored form missed three of the six helpers this issue names by hand, all on punctuation:
# `local work="$1" origin="$2"` puts two bindings on one line, and `local tmp; tmp=$(mktemp -d)`
# puts the declaration and the assignment on one line. A guard narrower than the claim it carries
# is this issue's own subject, so the miss is not a detail.
BIND_READ_PROCSUB = re.compile(
    r'^\s*(?:IFS=\S*\s+)?read\s+(?:-r\s+)?(?P<vars>[A-Za-z_][A-Za-z0-9_ ]*)\s*<\s*<\(')

_DECL = r'(?:local\s+|declare\s+|typeset\s+|export\s+)?'
_LEAD = r'(?:^|;|\s|\()'
FUNC_HEAD = re.compile(r'^\s*(?:function\s+)?[A-Za-z_][A-Za-z0-9_]*\s*\(\)\s*\{')


def _bind_res(var):
    v = re.escape(var)
    return (
        re.compile(_LEAD + _DECL + v + r'="?\$\{?[0-9]+\}?"?(?:\s|;|$)'),   # positional
        re.compile(_LEAD + _DECL + v + r'="?\$\('),                          # command substitution
        re.compile(_LEAD + _DECL + v + r'='),                                 # any other binding
    )


# A guard that makes an EMPTY operand impossible. `${v:?...}` is sufficient FOR P1a specifically —
# it refuses empty and unset — even though it does not reject a relative path, which is P1b and is
# tracked separately rather than silently folded in here.
GUARD = re.compile(
    r'assert_fixture_dir'
    r'|\$\{[A-Za-z_][A-Za-z0-9_]*:\?'
    r'|\|\|\s*(exit|return)'
    r'|^\s*case\s+"\$\{?[A-Za-z_][A-Za-z0-9_]*'
    r'|^\s*\[\[\s+-[dn]\s')


def _binding_of(lines, use_idx, var, skip):
    """Nearest preceding binding of `var`, and the form it took.

    Returns (binding_index, form), or None when the nearest binding cannot be empty (a literal) or
    the variable is never bound in this file — an inherited global, which is outside P1a's stated
    assembly of positionals and command substitutions.
    """
    if var.isdigit():
        return (use_idx, "positional-at-use")
    pos_re, sub_re, any_re = _bind_res(var)
    for j in range(use_idx - 1, -1, -1):
        if j in skip:
            continue
        l = lines[j]
        if l.lstrip().startswith("#"):
            continue
        if pos_re.search(l):
            return (j, "positional")
        if sub_re.search(l):
            return (j, "command-substitution")
        m = BIND_READ_PROCSUB.match(l)
        if m and var in m.group("vars").split():
            return (j, "read-process-substitution")
        # Any OTHER assignment ends the search: the nearest binding is what reaches the use site,
        # and this one is not a P1a shape.
        if any_re.search(l):
            return None
    return None


def scan_operand(paths):
    out = []
    for f in paths:
        lines = read_lines(f)
        if lines is None:
            continue
        skip = heredoc_lines(lines)
        for i, line in enumerate(lines):
            if i in skip or line.lstrip().startswith("#"):
                continue
            m = OPERAND_WRITE.search(line)
            if not m:
                continue
            var = m.group("var")
            b = _binding_of(lines, i, var, skip)
            if b is None:
                continue
            bind_idx, form = b
            # A guard anywhere between the binding and the use — inclusive of the binding line,
            # which is where `|| return 1` and `${1:?}` live.
            #
            # For the positional-at-use form the binding IS the use line, which would leave a
            # one-line window and mark `assert_fixture_dir "$1"` on the PRECEDING line as absent.
            # That is not a hypothetical: this scanner flagged its own sibling guard's Guard 3
            # harness, which asserts on one line and writes on the next. So the window widens back
            # to the enclosing function head — bounded there rather than by a line count, so a
            # guard in a DIFFERENT function cannot clear this one.
            if form == "positional-at-use":
                for k in range(i - 1, max(-1, i - 60), -1):
                    if FUNC_HEAD.match(lines[k]):
                        break
                    bind_idx = k
            guarded = False
            for k in range(bind_idx, i + 1):
                if k in skip:
                    continue
                if GUARD.search(lines[k]):
                    guarded = True
                    break
            if guarded:
                continue
            out.append((f, i + 1, form, m.group("verb"), line.strip()[:70]))
    return out


# --- CLI ------------------------------------------------------------------------------------------

def main(argv):
    rule = "cd"
    repo = None
    files = []
    it = iter(range(len(argv)))
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--rule":
            i += 1; rule = argv[i]
        elif a == "--repo":
            i += 1; repo = argv[i]
        else:
            files.append(a)
        i += 1

    if repo:
        pattern = "*.sh" if rule == "operand" else "*.test.sh"
        files = tracked_shell_files(repo, pattern)

    if rule == "operand":
        hits = scan_operand(files)
        for f, n, form, verb, src in hits:
            rel = os.path.relpath(f, repo) if repo else f
            print(f"{rel}:{n}: unasserted fixture dir ({form}) -> git -C write `{verb}`")
            print(f"    {src}")
    else:
        hits = scan_cd(files)
        for f, n, cd, wn, w in hits:
            rel = os.path.relpath(f, repo) if repo else f
            print(f"{rel}:{n}: unguarded `cd` -> `{w}` at line {wn}")
            print(f"    {cd}")
    print(f"FILES={len(files)}")
    print(f"SITES={len(hits)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
