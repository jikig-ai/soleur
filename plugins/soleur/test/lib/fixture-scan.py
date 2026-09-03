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
# `\S+` for the source ate the OPTION instead: `mv -f "$tmp" "$out"` captured `tmp` (the source,
# which mktemp clears) and never examined `$out`. Options are skipped explicitly, and the
# recursive-copy alternation covers `-a`/`-R` as well as `-r`.
RELATIVE_MVCP = re.compile(
    r'\b(?:mv|cp)\b(?:\s+-[a-zA-Z-]+)*\s+\S+\s+"\$\{?(?P<var>[A-Za-z_][A-Za-z0-9_]*|[0-9]+)\}?[/"]')

# Redirection targets that are CI plumbing, not fixture directories. Excluded by NAME because the
# shape is identical to a fixture write and no chain analysis can tell them apart: the runner sets
# them, they are absolute, and flagging them is how a guard stops being read.
CI_SINK_VARS = frozenset({"GITHUB_OUTPUT", "GITHUB_STEP_SUMMARY", "GITHUB_ENV", "GITHUB_PATH"})

_REL_ALIAS = re.compile(r'^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$')
_REL_DERIV = re.compile(r'^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/.*$')
_REL_CALL = re.compile(r'^\$\(\s*([A-Za-z_][A-Za-z0-9_]*)\b[^)]*\)$')
# mktemp yields an absolute path ONLY when it is given no destination of its own. Measured, three
# forms that do NOT and were previously classified absolute:
#   mktemp -d tmp.XXXXXX      -> tmp.nWeiP9        a SLASHLESS template is still relative to CWD
#   mktemp -dp "$R"           -> "$R"/tmp.XXXX     -p inside a short-flag CLUSTER
#   mktemp -d -p"$R"          -> "$R"/tmp.XXXX     -p with an ATTACHED argument
# So the rule is inverted from "does it look inherited" to "is it provably bare": absolute only
# when every argument is a flag, with `-t`/`--tmpdir=` excluded because they name a directory too.
_MKTEMP_TEMPLATE = re.compile(r'X{3,}')
_MKTEMP_DESTFLAG = re.compile(r'(?:^|\s)-[a-zA-Z]*p|--tmpdir|(?:^|\s)-[a-zA-Z]*t(?:\s|$)')


def _mktemp_class(val):
    """'mktemp-abs' when the call can only yield an absolute path, else 'mktemp-inherits'."""
    m = re.match(r'^\$\(\s*mktemp\b(?P<args>[^)]*)\)$', val)
    if not m:
        return None
    args = m.group("args")
    if _MKTEMP_DESTFLAG.search(args):
        return "mktemp-inherits"          # -p / --tmpdir / -t all name a directory
    for tok in args.split():
        if tok.startswith("-"):
            continue
        # a positional argument is a TEMPLATE; it is relative unless it starts at root
        if _MKTEMP_TEMPLATE.search(tok) or "/" in tok:
            return "mktemp-abs" if tok.lstrip('"').startswith("/") else "mktemp-inherits"
        return "mktemp-inherits"
    return "mktemp-abs"
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


_QUOTED = re.compile(r"'[^']*'" + r'|"[^"]*"')


def _strip_quoted(line):
    """Blank out BOTH quote kinds, so braces and tokens inside strings are not read as code."""
    return _QUOTED.sub(lambda m: " " * len(m.group(0)), line)


def _function_bodies(lines):
    """name -> (start_idx, end_idx). A ONE-LINE definition yields start == end, and every consumer
    must therefore scan an INCLUSIVE range; `range(end, start, -1)` is empty and silently skips it.

    Braces are counted with QUOTED SPANS REMOVED. A single `printf '{\n'` left the depth positive
    forever, ran the function's end to EOF, and let `_wrapper_root` pick up a LATER function's
    `echo "$t"` and its mktemp root — reporting a wrapper that emits a relative literal as
    absolute. jq programs, awk bodies and JSON fixtures all supply the unbalanced brace.
    """
    out = {}
    for i, l in enumerate(lines):
        m = FUNC_HEAD.match(l)
        if not m:
            continue
        name = re.match(r'^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)', l)
        if not name:
            continue
        bare = _strip_quoted(l)
        depth = bare.count('{') - bare.count('}')
        j = i
        while depth > 0 and j + 1 < len(lines):
            j += 1
            b = _strip_quoted(lines[j])
            depth += b.count('{') - b.count('}')
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
        # commonprefix is CHARACTER-wise, so `.../testing-extra/helpers.sh` outranked
        # `.../test/helpers.sh` for a file in `.../testing/`. Rank by shared path COMPONENTS.
        def _shared_components(cand):
            a = os.path.abspath(cand).split(os.sep)
            b = os.path.abspath(path).split(os.sep)
            n = 0
            for x, y in zip(a, b):
                if x != y:
                    break
                n += 1
            return n
        cands.sort(key=lambda c: -_shared_components(c))
        sl = read_lines(cands[0])
        if sl is None:
            continue
        for n, (lo, hi) in _function_bodies(sl).items():
            funcs.setdefault(n, (lo, hi, sl))
    cache[path] = funcs
    return funcs


def _classify_value(val):
    mk = _mktemp_class(val)
    if mk:
        return mk
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


def _binds_before_use(line, var):
    """True when an assignment to `var` ends before the first `"$var"` reference on this line."""
    v = re.escape(var)
    b = re.search(_LEAD + _DECL + v + r'=', line)
    u = re.search(r'"\$\{?' + v + r'\}?', line)
    return bool(b and u and b.end() <= u.start())


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
    # No `echo "$var"`. The value is whatever the LAST statement produced, so only that statement
    # may be read. A bare `\bmktemp\b` search over the whole body claimed absoluteness from a
    # mktemp whose output went to /dev/null while the function echoed a RELATIVE literal.
    for k in range(hi, lo - 1, -1):
        seg = _strip_quoted(blines[k]).strip().rstrip('}').strip()
        if not seg or seg.startswith('#'):
            continue
        if not re.search(r'\bmktemp\b', seg):
            return None                      # last statement is not a mktemp: cannot claim a root
        if re.search(r'>\s*/dev/null|>\s*"?\$', seg):
            return None                      # its output was redirected away, so it is not the value
        if re.search(r'\s-[a-zA-Z]*p|--tmpdir|\s-[a-zA-Z]*t(?:\s|$)', seg):
            return "mktemp-inherits"
        if re.search(r'mktemp[^;|]*\s[^\s;|-][^\s;|]*X{3,}', seg):
            return "mktemp-inherits"         # a template argument names a directory
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
            # A binding can sit on the SAME line as the use, ahead of it:
            #   VERDICT_LOG="$TMP/verdicts.txt"; : > "$VERDICT_LOG"
            # Walking strictly upward never sees it and reports never-bound, which is a FALSE
            # POSITIVE: the chain is resolvable and, here, mktemp-rooted. Retry inclusively, and
            # only accept a binding that ends before the use begins so a self-referential
            # assignment (`X="$X/sub"`) cannot resolve to itself.
            j2, val2 = _rhs_of(lines, use, cur, skip, lo=lo, inclusive=True)
            # The binding must END BEFORE the use BEGINS on that line. Testing only `j2 != use`
            # accepted a REBIND that follows the use — `rm -rf "$WORK"; WORK=$(mktemp -d)` cleared
            # a delete that ran against whatever `$WORK` held beforehand. The comment claimed this
            # check; the code did not have it.
            if j2 is None or j2 != use or not _binds_before_use(lines[use], cur):
                return "never-bound", cur
            j, val = j2, val2
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


# --- P1b guard recognition: predicates that prove ABSOLUTENESS, not merely non-emptiness ---------
#
# `scan_relative` used `_guard_res` — P1a's set — unchanged. That set answers "can this be EMPTY",
# and four of its five arms clear a RELATIVE site while proving nothing about it. Measured, each
# of these cleared `local d="$1/repo"; rm -rf "$d"`:
#
#   : "${d:?empty}"                  refuses empty and unset; says nothing about relative
#   [[ -n "$d" ]] || exit 1          same predicate, spelled long
#   case "$d" in *) : ;; esac        a catch-all that asserts nothing
#   mkdir -p "$d" || exit 1          `mkdir -p relative/dir` SUCCEEDS, so the abort proves the
#                                    OPPOSITE of what it was credited with
#
# 355 of 913 baseline rows were cleared this way. The baseline header already stated the rule this
# violates — "a guard that only rejected EMPTY would not be [sound], and must not be added to this
# rule's recognised set" — so the set is now built from that sentence rather than inherited.
#
# Two forms are recognised, and both must REJECT a relative path, not merely notice one:
#   1. `assert_fixture_dir "$var"` — its `case` has an explicit `*) ... exit` relative arm.
#   2. an inline `case "$var"` carrying BOTH an absolute-accept arm (`/*)`) and a default arm that
#      aborts. This is the shape a plugin script uses when it cannot take a test-helper dependency.
_SQUOTE = re.compile(r"'[^']*'")


def _strip_squotes(line):
    """Blank out single-quoted spans.

    A guard is a predicate, not a word. `echo 'TODO: assert_fixture_dir "$d" was removed'` cleared
    a live site by containing the assertion's NAME — the cdx() name-token gap this scanner exists
    to replace, reproduced inside the replacement.
    """
    return _SQUOTE.sub(lambda m: " " * len(m.group(0)), line)


def _case_proves_absolute(lines, start, var, skip):
    """A `case "$var"` block that accepts `/*` and aborts on the default arm."""
    v = re.escape(var)
    if not re.search(r'case\s+"?\$\{?' + v + r'\}?"?\s+in', _strip_squotes(lines[start])):
        return False
    saw_abs, saw_reject = False, False
    for k in range(start, min(start + 14, len(lines))):
        if k in skip:
            continue
        seg = _strip_squotes(lines[k])
        if re.search(r'(?:^|[\s|(])/\*\)', seg):
            saw_abs = True
        if re.search(r'(?:^|[\s|(])\*\)', seg) and re.search(r'\b(?:exit|return)\b', seg):
            saw_reject = True
        if 'esac' in seg:
            break
    return saw_abs and saw_reject


def _rel_guard_window(lines, use_idx):
    """First line the guard scan may read: the enclosing function head, else file start.

    Scanning from line 0 let an UNRELATED function that happens to use the same variable name
    clear a later unguarded site — measured, and exactly the bound P1a already applies to its own
    window for the same reason.
    """
    for k in range(use_idx, -1, -1):
        if FUNC_HEAD.match(lines[k]):
            return k
    return 0


def _rel_guarded(lines, use_idx, var, endvar, skip):
    names = [n for n in (var, endvar) if n]
    lo = _rel_guard_window(lines, use_idx)
    # A GLOBAL guarded once at top level is guarded for every later use, and bounding its window at
    # the enclosing function head would discard that — measured, it discarded the inline `case`
    # refusal on `$REPO_ROOT` in constraint-scaffold.sh, four sites. The widening is admitted ONLY
    # when the name is not rebound inside the function, so it cannot restore the cross-function
    # silencing the bound exists to stop: there, the name IS a local and the window stays closed.
    if lo > 0:
        rebound = False
        for n in names:
            rx = re.compile(_LEAD + _DECL + re.escape(n) + r'=')
            if any(rx.search(lines[k]) for k in range(lo, use_idx + 1)
                   if k not in skip and not lines[k].lstrip().startswith("#")):
                rebound = True
                break
        if not rebound:
            lo = 0
    for k in range(lo, use_idx + 1):
        if k in skip or lines[k].lstrip().startswith("#"):
            continue
        seg = _strip_squotes(lines[k])
        for n in names:
            if re.search(r'assert_fixture_dir\s+"?\$\{?' + re.escape(n) + r'\}?"?', seg):
                return True
            if _case_proves_absolute(lines, k, n, skip):
                return True
    return False


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
                if _rel_guarded(lines, i, var, endvar, skip):
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
