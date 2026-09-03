"""Shared corpus scanner for the fixture-safety guards (#7652, #7708).

WHY ONE MODULE AND NOT TWO COPIES. `fixture-cd-containment.test.sh` forbids the shape where a
failed `cd` redirects a git write into the caller's repository. Its sibling forbids the shape where
an EMPTY `-C` operand does the same thing without any `cd` at all. The two rules are different; the
machinery underneath them — which files are in the corpus, which lines are heredoc BODY rather than
code, which lines are comments, whether a `set -e` is in scope — is identical, and a comment in one
file asking the reader to keep it in step with another file is not an invariant. Sharing the module
is what makes the composition checkable instead of aspirational.

THE RULES

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

`scan_relative` — the P1b shape, added by #7708. Same operands, a different question: not "can
this be EMPTY" but "can this be RELATIVE, or rooted at `/` by an empty parent":

    setup() {
      local root="$1"                      # caller may pass a relative path
      local work="$root/repo"              # ...so this is relative too
      rm -rf "$work"                       # -> deletes relative to CWD
    }

SCOPE. `scan_operand` covers P1a — the EMPTY operand — only, and its verdicts are frozen: #7708
forbids changing `OPERAND_WRITE` or `scan_operand`, because P1a's baseline is a shrink-only
ratchet and a detector change would silently re-price every row in it. `scan_relative` therefore
carries its OWN binding resolver rather than extending `_binding_of`. The two rules ask different
questions and the verbs do not share a failure mode: measured, only `git -C` WIDENS on an empty
operand, `rm -rf ""` is a silent no-op and `mv a ""` errors. Stating that is the point — a silent
omission would read as coverage.

The `git -C` arm of `scan_relative` claims only the residue P1a structurally CANNOT see (sites
where `_binding_of` returns None). Overlapping the two would let one ratchet retire the other's
rows.
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
        elif s.endswith("("):   # `s == "("` is subsumed: "(".endswith("(") is True
            if depth == 0:
                for k in range(j + 1, idx):
                    if SET_E.match(lines[k]) and not lines[k].lstrip().startswith("#"):
                        return True
                return False
            depth -= 1
    return False


def read_lines(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read().split("\n")
    except OSError:
        return None


def tracked_shell_files(repo_root, pattern="*.sh"):
    """The corpus.

    `*.sh`, not `*.test.sh`. The narrower suffix misses `tests/hooks/test_hook_emissions.sh` (a
    `git -C "$path" init` helper the runner DOES run), `.github/scripts/test/test-*.sh`, sourced
    libraries such as `plugins/soleur/test/test-helpers.sh`, and standalone gate scripts. A corpus
    that excludes the files where the helpers actually live is a declaration site.
    """
    # `-z`, and the exit status is CHECKED. Without either: a path containing a space was split
    # into two nonexistent paths and silently dropped by the caller's `except OSError`, and any git
    # failure produced an empty corpus that reads byte-identically to a clean tree.
    r = subprocess.run(["git", "-C", repo_root, "ls-files", "-z", pattern],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"fixture-scan: `git ls-files` failed in {repo_root!r} "
                         f"(rc={r.returncode}): {r.stderr.strip()[:200]}")
    out = []
    for rel in r.stdout.split("\0"):
        if not rel:
            continue
        full = os.path.join(repo_root, rel)
        # A tracked symlink would be followed by open() — outside the repo, and potentially at an
        # unbounded target. There are zero tracked *.sh symlinks today; this keeps it that way.
        if os.path.islink(full):
            continue
        out.append(full)
    return out


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
    r'(?P<verb>commit|push|add\b|update-ref|checkout|switch|restore|reset|branch|merge|pull|rebase'
    r'|revert|cherry-pick|am|stage|clean|update-index|read-tree|write-tree|hash-object|commit-tree'
    r'|mktree|mktag|pack-refs|repack|prune-packed|replace|rerere|filter-branch|fast-import'
    r'|worktree\s+(?:add|remove|move|prune|repair|lock|unlock)'
    r'|remote\s+(?:add|remove|rm|set-url|set-head|rename|prune)'
    r'|notes\s+(?:add|append|copy|edit|remove|prune)'
    r'|reflog\s+(?:expire|delete)'
    r'|submodule\s+(?:add|update|deinit|sync|set-url|set-branch)'
    r'|sparse-checkout\s+(?:set|add|init|disable|reapply)'
    r'|subtree\s+(?:add|pull|push|merge|split)'
    r'|stash\s+(?:push|pop|apply|drop|clear|create|store|save)'
    r'|rm\b|mv\b|config|init|clone|tag|fetch|apply|gc|prune|symbolic-ref)\b'
)
# Verbs with READ subcommands are scoped to their mutating ones. `git worktree list`,
# `remote -v`, `notes show`, `reflog show`, `stash list` and `submodule status` are reads, and a
# guard that flags a read is a false positive — which is how a guard stops being read at all.
# `switch`, `restore` and `merge` were the load-bearing omissions: the first two are the modern
# spellings of `checkout`/`reset`, and there is a live instance of the third —
# `.claude/hooks/pre-merge-rebase.sh` runs `git -C "$WORK_DIR" merge origin/main` where WORK_DIR
# derives from model-controlled JSON stdin. It was invisible on TWO axes at once: the verb was
# absent AND the binding is an alias (`WORK_DIR="$HOOK_CWD"`), which `_binding_of` treats as a
# terminator. The alias axis is P1b-adjacent and tracked; the verb axis is closed here.

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


# A guard that makes an EMPTY operand impossible, CORRELATED WITH THE OPERAND.
#
# The first version was variable-agnostic and matched anywhere in the window, which made it
# defeatable four ways — all four proven with fixtures that scanned clean:
#   (a) `# assert_fixture_dir "$dir"   <- removed, TODO restore`   (a COMMENT; the guard window
#       did not skip comment lines, though the write-match loop did)
#   (b) `case "$MODE" in fast) : ;; esac`            (an unrelated case)
#   (c) `[[ -n "$SOMETHING_ELSE" ]] || true`         (an unrelated test)
#   (d) `mkdir -p /tmp/x || return 1`                (an unrelated || return)
# Consequence: each of the six helpers this issue remediated has exactly ONE assertion call, so
# deleting it and leaving a comment that merely NAMES it kept the ratchet green — i.e. the fix
# could be reverted invisibly. That is the `cdx()` name-token gap this scanner exists to replace,
# reproduced inside the replacement.
#
# `${v:?...}` remains sufficient FOR P1a specifically: it refuses empty and unset. It does not
# reject a relative path, which is P1b and tracked separately rather than silently folded in.
#
# NOT recognised, deliberately: `|| true` and `|| <fallback>`. Both are the OPPOSITE of a guard —
# they permit the failure, and live sites sit next to them. No count is given here on purpose:
# three defensible readings of "a site next to a fallback" produced three different numbers
# (8 / 11 / 12) depending on whether the match is per-site or per-occurrence and whether it is
# anchored at end-of-statement. A number that needs its predicate published alongside it is not
# carrying the argument — the property is. Rationale lives in
# fixture-dir-operand-assert.baseline.txt's 2026-09-03 entry.
#
# ALSO not recognised: `|| { …; exit N; }`, a brace-group abort. That IS a real abort and the
# eight sites it guards in .github/scripts/test/test-infra-suite-registration-mutations.sh are
# acknowledged in the baseline rather than detected. A pattern for it was written and REVERTED —
# see the baseline's 2026-09-03 entry for the five shapes that satisfied it while aborting
# nothing. Recognising a brace group correctly needs shell semantics (quoting, statement
# boundaries, subshell scope, function scope) that a line-oriented regex cannot supply, and a
# widening that silences a genuinely unguarded site is strictly worse than the false positives
# it removes.
def _guard_res(var):
    v = re.escape(var)
    return (
        # the assertion, applied to THIS operand
        re.compile(r'assert_fixture_dir\s+"?\$\{?' + v + r'\}?"?'),
        # ${var:?...} / ${var:?} at the binding
        re.compile(r'\$\{' + v + r':\?'),
        # `... || exit` / `|| return` on a line that MENTIONS this operand — either by reference
        # (`"$d" || return`) or as the ASSIGNMENT being guarded (`d=$(mktemp -d) || return 1`,
        # which is the dominant real shape and mentions `d=`, never `$d`).
        re.compile(r'(?:\$\{?' + v + r'\}?|(?:^|;|\s)(?:local\s+|declare\s+)?' + v + r'=)'
                   r'.*\|\|\s*(?:exit|return)'),
        # a case/test whose SUBJECT is this operand
        re.compile(r'(?:case|\[\[)\s+.*"\$\{?' + v + r'\}?"'),
    )


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
            # which is where `|| return 1` and `${1:?}` live. COMMENT LINES ARE SKIPPED: the
            # write-match loop skipped them from the start and this one did not, so a commented-out
            # assertion read as a live one.
            #
            # For the positional-at-use form the binding IS the use line, which would leave a
            # one-line window and mark `assert_fixture_dir "$1"` on the PRECEDING line as absent.
            # That is not a hypothetical: this scanner flagged its own sibling guard's Guard 3
            # harness, which asserts on one line and writes on the next. So the window widens back
            # to the enclosing function head — bounded there rather than by a line count, so a
            # guard in a DIFFERENT function cannot clear this one.
            #
            # The walk starts at `i`, NOT `i - 1`. A ONE-LINE function definition
            # (`f() { git -C "$1" add -A; }`) is its own head, so starting above it stepped over
            # that head and ran on to the head of the PREVIOUS function — swallowing an unrelated
            # body, where any guard on a same-named positional cleared the site. Measured: a
            # `${1:?}` inside `new_repo()` silenced a genuinely unguarded `commit_all()` two lines
            # below it (SITES=0; 1 after this fix), which is exactly the placement the #7709
            # burn-down had to correct by hand in two legal-lint suites. The comment above was
            # asserting an invariant the code did not have.
            if form == "positional-at-use":
                for k in range(i, max(-1, i - 60), -1):
                    if FUNC_HEAD.match(lines[k]):
                        break
                    bind_idx = k
            guarded = False
            guards = _guard_res(var)
            for k in range(bind_idx, i + 1):
                if k in skip or lines[k].lstrip().startswith("#"):
                    continue
                if any(g.search(lines[k]) for g in guards):
                    guarded = True
                    break
            if guarded:
                continue
            out.append((f, i + 1, form, m.group("verb"), line.strip()[:70]))
    return out


# --- P1b: a RELATIVE or ROOT-ANCHORED operand ---------------------------------------------------
#
# P1a asks whether the operand can be EMPTY. P1b asks whether it can be RELATIVE, or whether an
# empty PARENT can root it at `/`. The two do not share a failure mode and are not folded together:
# measured, only `git -C ""` widens silently, `rm -rf ""` is a no-op and `mv a ""` errors.
#
# THREE FAMILIES, named by what they do rather than by verb (see #7708):
#   widening       a relative `git -C` / `rm -rf` / redirection target resolves against whatever
#                  CWD happens to be, which for these suites is the developer's live worktree.
#   root-anchored  `"$X/f"` with `$X` empty is `/f`, not `f`. Usually loud, occasionally not.
#   loud-failure   `mv a "$X"` / `cp -r a "$X"` into an empty destination exits non-zero.
#
# WHY THIS RULE CARRIES ITS OWN BINDING RESOLVER AND DOES NOT REUSE `_binding_of`.
# `_binding_of` stops at the nearest assignment and returns None when that assignment is not a P1a
# shape. That is correct for P1a and useless here: measured over 921 tracked files, 199 of the 497
# named-variable `git -C` write sites terminate that way, and EVERY one of them has a real binding.
# The relativity question is a property of the chain ROOT, so the chain has to be walked:
#   X="$tmp/work"  ->  tmp=$(mktemp -d)   ->  absolute, cannot be relative
#   X="$1/work"    ->  unresolved caller  ->  candidate
# Extending `_binding_of` itself would change P1a's verdicts, which #7708 explicitly forbids.
#
# WHAT COUNTS AS PROVABLY ABSOLUTE, and the two things that measurably do NOT:
#   `$(mktemp -d)`, `$(mktemp)`, `$(mktemp -d -t pre.XXXXXX)`  -> absolute
#   `$(mktemp -d -p "$R")`, `$(mktemp -d "$ROOT/c.XXXXXX")`    -> INHERITS `$R` / `$ROOT`
# The second line is the one that bites. A path-bearing TEMPLATE inherits its prefix exactly as
# `-p` does, and classifying it absolute silently cleared 114 `rm -rf` and 153 redirection sites.
# Note also that mktemp's absoluteness is ENVIRONMENTAL, not lexical: `TMPDIR=reldir mktemp -d`
# returns `reldir/tmp.XXXX`, measured. It is treated as absolute here because this corpus has zero
# relative `TMPDIR` literals and zero relative `-p` arguments — established with a positive control
# showing the pattern can match — not because mktemp guarantees it.

RELATIVE_RM = re.compile(
    r'\brm\s+(?:-[a-zA-Z]+\s+)*-[a-zA-Z]*r[a-zA-Z]*f?[a-zA-Z]*\s+'
    r'"\$\{?(?P<var>[A-Za-z_][A-Za-z0-9_]*|[0-9]+)\}?[/"]')
RELATIVE_REDIR = re.compile(
    r'(?<![0-9<>])>>?\s*"\$\{?(?P<var>[A-Za-z_][A-Za-z0-9_]*|[0-9]+)\}?[/"]')
RELATIVE_MVCP = re.compile(
    r'\b(?:mv|cp\s+-r[a-zA-Z]*)\s+\S+\s+"\$\{?(?P<var>[A-Za-z_][A-Za-z0-9_]*|[0-9]+)\}?[/"]')

# Redirection targets that are CI plumbing, not fixture directories. Excluded by NAME because the
# shape is identical to a fixture write and no chain analysis can tell them apart: the runner sets
# them, they are absolute, and flagging them is how a guard stops being read.
CI_SINK_VARS = frozenset({"GITHUB_OUTPUT", "GITHUB_STEP_SUMMARY", "GITHUB_ENV", "GITHUB_PATH"})

_REL_ALIAS = re.compile(r'^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$')
_REL_DERIV = re.compile(r'^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/.*$')
_REL_CALL = re.compile(r'^\$\(\s*([A-Za-z_][A-Za-z0-9_]*)\b[^)]*\)$')
_MKTEMP_ABS = re.compile(
    r'^\$\(\s*mktemp\b(?![^)]*(?:\s-p\s|--tmpdir))(?![^)]*/[^\s")]*X{3,})[^)]*\)$')
_MKTEMP_INHERIT = re.compile(r'^\$\(\s*mktemp\b[^)]*(?:\s-p\s|--tmpdir|/[^\s")]*X{3,})')
# An emit can sit mid-line, after `;` or `{`. A ONE-LINE wrapper keeps it exactly there, and
# anchoring this at `^` made every one-line fixture wrapper unresolvable.
_EMITS = re.compile(r'(?:^|;|\{)\s*(?:echo|printf)\b[^;]*?"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?"')
_SOURCE = re.compile(r'^\s*(?:source|\.)\s+"?([^"\s;]+)"?')


def _extract_value(s, pos):
    """The value token beginning at s[pos].

    Quote-aware AND substitution-aware: a closing quote INSIDE `$( )` does not end the value.
    `X="$(mktemp -d "$ROOT")"` truncated to `$(mktemp -d ` under a naive reader, which then
    failed every mktemp test and reported the site as an unresolved candidate.
    """
    n = len(s)
    if pos >= n:
        return ""
    out = []
    if s[pos] in '"\'':
        q = s[pos]; pos += 1; depth = 0
        while pos < n:
            c = s[pos]
            if c == '\\' and pos + 1 < n:
                out.append(s[pos + 1]); pos += 2; continue
            if c == '$' and pos + 1 < n and s[pos + 1] == '(':
                depth += 1; out.append('$('); pos += 2; continue
            if c == ')' and depth:
                depth -= 1; out.append(c); pos += 1; continue
            if c == q and depth == 0:
                break
            out.append(c); pos += 1
        return "".join(out)
    depth = 0
    while pos < n:
        c = s[pos]
        if c == '$' and pos + 1 < n and s[pos + 1] == '(':
            depth += 1; out.append('$('); pos += 2; continue
        if c == ')' and depth:
            depth -= 1; out.append(c); pos += 1; continue
        if depth == 0 and c in ' \t;|&':
            break
        out.append(c); pos += 1
    return "".join(out)


def _function_bodies(lines):
    """name -> (start_idx, end_idx). A ONE-LINE definition yields start == end, and every consumer
    must therefore scan an INCLUSIVE range; `range(end, start, -1)` is empty and silently skips it.
    """
    out = {}
    for i, l in enumerate(lines):
        m = FUNC_HEAD.match(l)
        if not m:
            continue
        name = re.match(r'^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)', l)
        if not name:
            continue
        depth = l.count('{') - l.count('}')
        j = i
        while depth > 0 and j + 1 < len(lines):
            j += 1
            depth += lines[j].count('{') - lines[j].count('}')
        out[name.group(1)] = (i, j)
    return out


def _literal_tail(arg):
    """Trailing literal path fragment of a `source` argument: `"$V/lib/x.sh"` -> `lib/x.sh`."""
    s = re.sub(r'\$\([^)]*\)', '\x00', arg)
    s = re.sub(r'\$\{?[A-Za-z_][A-Za-z0-9_]*\}?', '\x00', s)
    tail = s.split('\x00')[-1].lstrip('/')
    return tail if tail.endswith('.sh') else None


def _extended_funcs(path, lines, corpus, cache):
    """Same-file functions plus, one hop out, functions from sourced helpers.

    Fixture wrappers frequently live in a shared `test-helpers.sh`, so a resolver that only reads
    the current file reports every `d=$(new_fixture)` as unresolved.
    """
    if path in cache:
        return cache[path]
    funcs = {n: (lo, hi, lines) for n, (lo, hi) in _function_bodies(lines).items()}
    for l in lines:
        m = _SOURCE.match(l)
        if not m:
            continue
        tail = _literal_tail(m.group(1))
        if not tail:
            continue
        cands = [p for p in corpus if p.replace("./", "").endswith(tail)]
        if not cands:
            continue
        cands.sort(key=lambda p: -len(os.path.commonprefix(
            [os.path.abspath(p), os.path.abspath(path)])))
        sl = read_lines(cands[0])
        if sl is None:
            continue
        for n, (lo, hi) in _function_bodies(sl).items():
            funcs.setdefault(n, (lo, hi, sl))
    cache[path] = funcs
    return funcs


def _classify_value(val):
    if _MKTEMP_INHERIT.match(val):
        return "mktemp-inherits"
    if _MKTEMP_ABS.match(val):
        return "mktemp-abs"
    if _REL_ALIAS.match(val):
        return "alias"
    if _REL_DERIV.match(val):
        return "derived"
    if val.startswith("/"):
        return "absolute-literal"
    if _REL_CALL.match(val):
        return "call"
    if val.startswith("$("):
        return "other-cmdsubst"
    return "other"


def _rhs_of(lines, upto, var, skip, lo=0, inclusive=False):
    """Nearest binding of `var` at or before `upto`.

    `inclusive` reads line `upto` itself, which is where a ONE-LINE wrapper keeps both its binding
    and its emit (`f() { local d="$T/x"; echo "$d"; }`).
    """
    v = re.escape(var)
    rx = re.compile(_LEAD + _DECL + v + r'=')
    start = upto if inclusive else upto - 1
    for j in range(start, lo - 1, -1):
        if j in skip or lines[j].lstrip().startswith("#"):
            continue
        m = rx.search(lines[j])
        if m:
            return j, _extract_value(lines[j], m.end())
    return None, None


def _wrapper_root(fname, funcs, depth):
    """Root class of what same-file-or-sourced function `fname` emits."""
    if depth > 4 or fname not in funcs:
        return None
    lo, hi, blines = funcs[fname]
    one_line = (lo == hi)
    for k in range(hi, lo - 1, -1):
        m = _EMITS.search(blines[k])
        if m:
            return _chain_root(blines, k, m.group(1), set(), funcs,
                               depth + 1, lo=lo, inclusive=one_line)[0]
    for k in range(hi, lo - 1, -1):
        if re.search(r'\bmktemp\b', blines[k]):
            seg = blines[k]
            if re.search(r'\s-p\s|--tmpdir', seg) or re.search(r'mktemp[^;|]*/[^\s";|]*X{3,}', seg):
                return "mktemp-inherits"
            return "mktemp-abs"
    return None


def _chain_root(lines, use_idx, var, skip, funcs, depth=0, lo=0, inclusive=False):
    """Walk aliases and derivations to the root binding. Returns (root_class, final_var)."""
    cur, use, d, inc = var, use_idx, 0, inclusive
    while d < 8:
        d += 1
        j, val = _rhs_of(lines, use, cur, skip, lo=lo, inclusive=inc)
        inc = False
        if j is None:
            return "never-bound", cur
        k = _classify_value(val)
        if k == "alias":
            cur, use = _REL_ALIAS.match(val).group(1), j
            continue
        if k == "derived":
            cur, use = _REL_DERIV.match(val).group(1), j
            continue
        if k == "call":
            return (_wrapper_root(_REL_CALL.match(val).group(1), funcs, depth)
                    or "call-unresolved"), cur
        return k, cur
    return "deep", cur


# A root that cannot be relative and cannot be empty. Everything else is a candidate.
_ROOT_SAFE = frozenset({"mktemp-abs", "absolute-literal"})

_REL_FAMILIES = (
    ("git-C", None),          # OPERAND_WRITE, restricted to what P1a structurally cannot see
    ("rm-rf", RELATIVE_RM),
    ("redirect", RELATIVE_REDIR),
    ("mv-cp", RELATIVE_MVCP),
)


def scan_relative(paths, corpus=None):
    """P1b: operands whose chain root is neither provably absolute nor guarded."""
    corpus = corpus if corpus is not None else paths
    cache = {}
    out = []
    for f in paths:
        lines = read_lines(f)
        if lines is None:
            continue
        skip = heredoc_lines(lines)
        funcs = _extended_funcs(f, lines, corpus, cache)
        for fam, rx in _REL_FAMILIES:
            pat = OPERAND_WRITE if rx is None else rx
            for i, line in enumerate(lines):
                if i in skip or line.lstrip().startswith("#"):
                    continue
                m = pat.search(line)
                if not m:
                    continue
                var = m.group("var")
                if var.isdigit():
                    continue
                if fam == "redirect" and var in CI_SINK_VARS:
                    continue
                # The git -C arm claims ONLY the residue P1a cannot see. Anything P1a can resolve
                # is P1a's to report, and reporting it twice is how two ratchets start disagreeing.
                if fam == "git-C" and _binding_of(lines, i, var, skip) is not None:
                    continue
                root, endvar = _chain_root(lines, i, var, skip, funcs)
                if root in _ROOT_SAFE:
                    continue
                guards = _guard_res(var) + _guard_res(endvar)
                if any(not (k in skip or lines[k].lstrip().startswith("#"))
                       and any(g.search(lines[k]) for g in guards)
                       for k in range(0, i + 1)):
                    continue
                out.append((f, i + 1, fam, root, line.strip()[:70]))
    return out



# --- CLI ------------------------------------------------------------------------------------------

def main(argv):
    rule = "cd"
    repo = None
    files = []
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
        # ONE corpus for both rules: `*.sh`.
        #
        # The cd rule used to walk only `*.test.sh` while the operand rule walked `*.sh`, which
        # meant this module's own docstring argument — "a corpus that excludes the files where the
        # helpers actually live is a declaration site" — was made for one rule and denied to the
        # other. That mattered more than it looks: once CWD isolation was measured out of the plan
        # (see the Phase 0 addendum), `scan_cd` became one of only two remaining covers for the
        # lost-`cd` class (#7553), and it was covering 376 of 901 tracked shell files.
        #
        # Measured before widening: `scan_cd` over `*.sh` returns the same 0 hits as over
        # `*.test.sh`, so this costs nothing today and closes the gap for every file added later.
        files = tracked_shell_files(repo, "*.sh")

    if rule not in ("operand", "cd", "relative"):
        raise SystemExit(
            f"fixture-scan: unknown --rule {rule!r} (want 'operand', 'cd' or 'relative')")

    if rule == "relative":
        hits = scan_relative(files, corpus=files)
        for f, n, fam, root, src in hits:
            rel = os.path.relpath(f, repo) if repo else f
            print(f"{rel}:{n}: operand not provably absolute ({fam}, root={root})")
            print(f"    {src}")
    elif rule == "operand":
        hits = scan_operand(files)
        for f, n, form, verb, src in hits:
            rel = os.path.relpath(f, repo) if repo else f
            print(f"{rel}:{n}: unasserted fixture dir ({form}) -> git -C write `{verb}`")
            print(f"    {src}")
    else:  # rule == "cd"
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
