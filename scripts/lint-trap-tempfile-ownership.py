#!/usr/bin/env python3
"""Lint shell scripts for tempfile-cleanup OWNERSHIP defects (#6734).

Two rules, deliberately narrow. Both encode defects that were found in production
code, reproduced, and fixed in this PR; neither is a style preference.

RULE (a) -- SUBSHELL-APPEND
    A helper that appends to a cleanup array (`ARR+=(...)`) *and* is invoked via
    command substitution `$(helper)`.

    Command substitution runs the helper in a SUBSHELL, so the append mutates the
    subshell's copy of the array and vanishes on subshell exit. The parent array
    stays empty and the `trap 'rm -f "${ARR[@]}"' EXIT` expands to `rm -f ""`,
    owning nothing. This is exactly what scripts/content-publisher.sh did at six
    call sites. Fix: allocate in the helper, register in the PARENT scope.

RULE (c) -- MKTEMP WITH NO OWNING TRAP
    A file that calls `mktemp`, registers no cleanup trap (`EXIT` or `RETURN`)
    anywhere, and whose offending allocation was ADDED by the current diff.

    This is the "class-b" population: 102 files repo-wide at time of writing.
    Most are short-lived CI scripts where the leak is bounded, so the existing
    population is ACCEPTED (see ADR-129) rather than fixed file-by-file. Rule (c)
    is therefore scoped to ADDED LINES: it gates NEW entrants only. Scoping it to
    changed FILES was tried and was wrong -- touching any accepted file then demanded
    you pay off its pre-existing debt, which is how a gate gets switched off. Without
    rule (c) entirely, the accept would be a pile nobody fences (the #6713 gap).

    Ratchet: scripts/lint-trap-tempfile-ownership.highwater records the accepted
    population size. `--census` recomputes it; CI asserts the live count never
    exceeds it, so the accept can only improve.

DELIBERATELY NOT IMPLEMENTED -- rule (b), "trap replacement by superset"
    A rule that tries to flag a second `trap ... EXIT` whose body is not a
    superset of the first cannot be made coherent. It would have to model
    subshell scope (`provision-hetzner.sh` is SAFE precisely because its second
    trap sits inside `( … )`) and intentional handoff (`vendor-pin-integrity.
    test.sh` uses `trap - EXIT` CORRECTLY). One analyzer cannot hold two
    contradictory models of scope, and a rule that fires on correct code is
    disabled within a week. The trap-replacement defect in
    scripts/skill-freshness-aggregate.sh is instead guarded behaviourally, by
    that script's own suite.

RULE (d) -- ALLOCATION WITH NO CLEANUP CONSTRUCT (non-test *.py, *.ts, *.mjs, *.js)
    A file that allocates scratch (`mkdtemp`, `mkdtempSync`, `mkstemp`, `mktemp`,
    `NamedTemporaryFile(delete=False)`), contains no cleanup construct and no owner
    marker, and whose allocation line was ADDED by the current diff. Deliberately NARROW.

    It must LEX, not grep, because a line grep is satisfied (and triggered) by its own
    prose: Python is read through `ast` (comments and string literals cannot satisfy or
    trigger it; a file `ast` cannot parse is reported as UNPARSED -- RED when its raw
    text contains an allocation token, never a crash and never a silent pass); TS/JS goes
    through a comment-, string-, template- and regex-literal masking pass, then a token
    match. Cleanup is FILE-LEVEL, like rule (c)'s trap: it asks "does this file own any
    removal", not "does this removal reach this allocation".

    Cleanup constructs (a REMOVAL CALL, never mere scaffolding):
      Python  rmtree, rmdir, removedirs, unlink, os.remove, .cleanup(), addCleanup,
              addfinalizer, TemporaryDirectory, atexit.register, and
              subprocess.<run|call|check_call|check_output|Popen>(["rm", ...]).
      TS/JS   rmSync, rm(, rmdirSync, rmdir(, unlinkSync, unlink(, rimraf, removeSync.
    `afterAll` / `afterEach` / `finally` / `process.on("exit")` are NOT accepted alone:
    they only SCHEDULE code; the removal call inside them is what counts, and it is
    already in the list. Removal by shelling out inside a string (`execSync("rm -rf x")`)
    is not recognised (a string is exactly what the lexer must not trust) -- annotate it.
    Owner markers: `ensure_scratch_session` / `ensureScratchSession` /
    `soleur_scratch_mark_owned` / `mark_owned` calls, the `SOLEUR_SCRATCH_SESSION_ROOT`
    identifier, or a non-docstring string literal beginning `.soleur-owned` (the ownership
    marker the reaper keys on).

    Test files are structurally excluded and counted separately (`excluded-tests` in
    `--census-detail`), never exempted by name alone. A file is excluded only when it is
    test-shaped (`test_*.py`, `*_test.py`, `conftest.py`, `*.test.*`, `*.spec.*`, or under a
    `test/`, `tests/`, `__tests__/` directory) AND sits under a runner session root,
    derived the way `.claude/hooks/incident-sandbox-coverage.test.sh` derives its covered
    roots: a tracked `bunfig.toml` with a `preload = [...]` or `vitest.config.ts` with a
    `globalSetup: [...]` whose declared entry file exists covers TS/JS under its directory;
    a tracked `conftest.py` covers Python under its directory. A test-named file outside
    every root is in the population like any script. (The derivation checks that the
    registration exists, not what the entry calls; the call-order and call-presence
    assertions live in the coverage suite.)

RULE (e) -- HARD-CODED /tmp OR /var/tmp BASE ON AN ALLOCATION
    A `mktemp` (shell), `mkdtemp`/`mkstemp`/`mktemp`/`NamedTemporaryFile` (Python) or
    `mkdtemp`/`mkdtempSync` (TS/JS) call whose argument list carries a literal `/tmp` or
    `/var/tmp` base. That base bypasses every per-run scratch root, so no session reaper
    can claim what it creates. `${TMPDIR:-/tmp}` is NOT a literal base (it honours TMPDIR),
    nor is `os.tmpdir()`/`tempfile.gettempdir()`. Applies to ALL files (tests too), added
    lines in default mode, whole file for explicit paths. Known limit: a base routed through
    a variable (`const B = "/tmp"; mkdtempSync(join(B, ...))`) is not seen.

ESCAPE HATCH (mandatory -- a gate without one dies at its first false positive)
    `# lint-trap-ownership: ok <reason>`   (`//` in TS/JS)
    Must carry a non-empty reason; a bare marker is itself an error. Place it on
    the offending line or the line immediately above. Honoured by rules (a), (c), (d), (e).

Modes:
    full-scan (default)   every tracked `*.sh`
    --changed             only files changed vs the merge base (rule (c) is
                          ALWAYS restricted to this set regardless of mode)
    --census              print the class-b (shell) population count and exit 0
    --census-tspy         print the rule (d) TS/PY population count and exit 0
    --census-detail       print every counter (shell, rule-d, rule-e, excluded tests,
                          files scanned per family, unparsed py) and exit 0
    --check-highwater     assert every census is at or below its highwater AND that a
                          highwater edited in this diff moved by exactly the amount the
                          census moved, comparing against the MERGE-BASE copy of the
                          highwater file (a working-copy compare lets one diff lower the
                          ratchet and absorb the growth it was meant to catch)
    explicit paths        scan exactly those files, WHOLE-file (lefthook / test
                          harness). Rule (c) is not line-scoped here: naming a path
                          is already the scoping decision, and deferring it to git
                          history would make the fixture suite expire on merge.

Exit codes:
    0  clean
    1  one or more violations (each printed `file:line: ...` on stderr)
    2  argument or git error, or a FLOOR breach: a walk that returns zero files of a
       family is "nothing checked", which is not "clean"
"""

from __future__ import annotations

import argparse
import ast
import posixpath
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
HIGHWATER_FILE = Path(__file__).resolve().parent / "lint-trap-tempfile-ownership.highwater"
TSPY_HIGHWATER_FILE = Path(__file__).resolve().parent / "lint-trap-tempfile-ownership-tspy.highwater"

# Language families. Rules (a)/(c) stay shell-`.sh`-only (unchanged); (e) also sees `.bash`.
SHELL_EXT = (".sh",)
SHELL_E_EXT = (".sh", ".bash")
PY_EXT = (".py",)
TS_EXT = (".ts", ".mjs", ".js")
ALL_EXT = SHELL_E_EXT + PY_EXT + TS_EXT

# `ARR+=( ... )` -- an append to a shell array, in COMMAND POSITION.
#
# Deliberately NOT anchored at line start. The `^\s*` form this replaced could only ever
# see an append that began its own line, which silently exempted the single highest-value
# shape: the one-liner registration helper.
#
#     mktmp() { local p; p=$(mktemp "$@"); TMP_PATHS+=("$p"); printf '%s' "$p"; }
#
# That is a real leak (the append runs in the `$( )` subshell and is discarded, so the
# EXIT trap iterates an empty array) and it scanned clean -- the append sits mid-line,
# after two `;` separators. The anchor, not the logic, was the blind spot.
#
# Uses the same command-position alternation as MKTEMP below: line start, after a
# `;` / `&&` / `||` / `|` separator, after a `{` or `(` block opener, or after
# then/do/else. Matching a bare `\w+\+=\(` anywhere would be the anchor-on-a-token bug
# (cq-assert-anchor-not-bare-token) -- it would fire on the string `"TMP_PATHS+=("` in
# a heredoc or an error message.
ARRAY_APPEND = re.compile(r'(?:^|[;&|{(]|\bthen\b|\bdo\b|\belse\b)\s*(\w+)\+=\(')
# `name() {` or `function name {` -- a function definition opening.
FUNC_DEF = re.compile(r'^\s*(?:function\s+)?(\w+)\s*\(\)\s*\{|^\s*function\s+(\w+)\s*\{')
# A cleanup trap registration. Anchored on the `trap` keyword and the signal name so a
# comment merely *mentioning* traps cannot satisfy it.
#
# RETURN counts as ownership, not just EXIT. A per-function `trap 'rm -rf "$d"' RETURN`
# fires when the function returns and is BETTER scoped than a process-wide EXIT trap for
# a test harness that allocates per case. An EXIT-only anchor flagged
# inngest-inventory.test.sh, which carries THIRTY correct RETURN traps -- exactly the
# fires-on-correct-code failure that gets a gate switched off.
#
# Not anchored at line start: these are frequently written mid-line after a `;`
# (`local d; d=$(mktemp -d); trap 'rm -rf "$d"' RETURN`).
TRAP_EXIT = re.compile(r'(?:^|;)\s*trap\s+.*\b(?:EXIT|RETURN)\b')
# `mktemp` in COMMAND POSITION -- not merely the word somewhere on the line.
#
# A bare `\bmktemp\b` is the classic anchor-on-a-token bug
# (cq-assert-anchor-not-bare-token). It matched this gate's OWN test file, where the
# word appears inside string data -- a fixture filename (`bad-mktemp-no-trap.sh.fixture`)
# and an assertion needle ("rule (c) mktemp with no owning trap") -- neither of which
# allocates anything. Stripping quoted strings is not the fix either: the real
# invocation is frequently written `f="$(mktemp -d)"`, i.e. INSIDE double quotes.
#
# So anchor on the positions a command can actually start from: line start, inside
# `$( )`, inside backticks, or after a `;` / `&&` / `||` / `|` separator, a `{` or `(`
# block opener (`mk_root() { mktemp -d; }` is a real allocation), or then/do/else.
MKTEMP = re.compile(r'(?:^|\$\(|`|[;&|{(]|\bthen\b|\bdo\b|\belse\b)\s*mktemp\b')
# The escape hatch. The trailing group must be non-empty -- a bare marker is an error.
LOCAL_DECL = re.compile(r'(?:^|[;&|{(]|\bthen\b|\bdo\b|\belse\b)\s*(?:local|declare|typeset)\s+(\w+)')
ESCAPE = re.compile(r'(?:#|//)\s*lint-trap-ownership:\s*ok\b[ \t]*(.*)$')


def escaped(lines: list[str], idx: int) -> tuple[bool, str | None]:
    """Return (is_escaped, error). Honours the offending line and the one above."""
    for probe in (idx, idx - 1):
        if probe < 0:
            continue
        m = ESCAPE.search(lines[probe])
        if m:
            if not m.group(1).strip():
                return False, (
                    f"{probe + 1}: `lint-trap-ownership: ok` with no reason -- the "
                    f"escape hatch must state WHY this site is safe"
                )
            return True, None
    return False, None


def strip_literals(line: str) -> str:
    """Drop string CONTENT that bash treats as literal, keeping live code.

    Bash semantics, and the reason a cruder pass is wrong in both directions:
      * single quotes are fully literal      -> drop the whole span
      * double quotes are literal EXCEPT for `$( … )` / backticks -> keep only those

    Without this, `mktemp` appearing as DATA is read as an allocation: a fixture
    filename, an assertion message, or a `|`-delimited test-case string all matched an
    earlier anchor and flagged this gate's own test file. Simply deleting every quoted
    span would be the opposite error, because the real allocation is often written
    `work="$(mktemp -d)"` -- inside double quotes.
    """
    def match_paren(s: str, open_idx: int) -> int:
        """Index of the `)` matching the `(` at open_idx, honouring nesting."""
        depth = 0
        for k in range(open_idx, len(s)):
            if s[k] == "(":
                depth += 1
            elif s[k] == ")":
                depth -= 1
                if depth == 0:
                    return k
        return len(s) - 1

    def take_subst(s: str, i: int, out: list[str]) -> int | None:
        """Emit a `$( … )` or backtick span verbatim; return the new index."""
        if s[i] == "$" and i + 1 < len(s) and s[i + 1] == "(":
            j = match_paren(s, i + 1)
            out.append(s[i:j + 1])
            return j + 1
        if s[i] == "`":
            j = s.find("`", i + 1)
            j = len(s) - 1 if j == -1 else j
            out.append(s[i:j + 1])
            return j + 1
        return None

    out: list[str] = []
    i = 0
    n = len(line)
    mode = "normal"
    while i < n:
        ch = line[i]
        if mode == "single":
            if ch == "'":
                mode = "normal"
            out.append(" ")
            i += 1
            continue
        # A command substitution is live in BOTH normal and double-quoted state, and its
        # body may itself contain quotes -- `"$(mktemp "${DIR}/x.XXXXXX")"` is the common
        # production shape. Matching the closing paren by DEPTH rather than scanning to
        # the next quote is what keeps that visible; an earlier draft truncated the span
        # at the inner quote and silently stopped counting 14 files, four of them real
        # production allocations.
        nxt = take_subst(line, i, out)
        if nxt is not None:
            i = nxt
            continue
        if mode == "normal":
            if ch == "'":
                mode = "single"
                out.append(" ")
            elif ch == '"':
                mode = "double"
                out.append(" ")
            else:
                out.append(ch)
            i += 1
            continue
        # double-quoted literal content
        if ch == '"':
            mode = "normal"
        out.append(" ")
        i += 1
    return "".join(out)


def strip_comment(line: str) -> str:
    """Drop a trailing `#` comment. Crude but sufficient: we only need to keep a
    marker in a comment from being read as code, and we never parse strings that
    legitimately contain `#` for these two rules."""
    out = []
    quote = None
    for ch in line:
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in "'\"":
            quote = ch
            out.append(ch)
            continue
        if ch == "#":
            break
        out.append(ch)
    return "".join(out)


def find_functions(lines: list[str]) -> dict[str, tuple[int, int]]:
    """Map function name -> (start_idx, end_idx) by brace depth."""
    funcs: dict[str, tuple[int, int]] = {}
    i = 0
    while i < len(lines):
        m = FUNC_DEF.match(lines[i])
        if not m:
            i += 1
            continue
        name = m.group(1) or m.group(2)
        depth = 0
        started = False
        j = i
        while j < len(lines):
            code = strip_comment(lines[j])
            depth += code.count("{") - code.count("}")
            if "{" in code:
                started = True
            if started and depth <= 0:
                break
            j += 1
        funcs[name] = (i, j)
        i = j + 1
    return funcs


def trap_owned_arrays(lines: list[str]) -> set[str]:
    r"""Names referenced from inside a `trap ... EXIT` body.

    This is what makes rule (a) precise rather than merely suggestive. Appending to an
    array inside a `$(...)`-invoked function is only a DEFECT when the array is a
    cleanup array whose consumer -- the EXIT trap -- lives in the parent scope. Building
    a `local curl_args=()` and consuming it in the same function is the overwhelmingly
    common, entirely correct case (plugins/soleur/skills/community/scripts/discord-setup.sh,
    apps/web-platform/infra/git-data-pre-receive.test.sh). An earlier draft of this rule
    flagged those, which is precisely the "fires on correct code, disabled within a week"
    failure this gate must avoid.

    Traps come in two shapes and BOTH must be resolved:

      trap 'rm -f "${_TMPFILES[@]}"' EXIT      # inline body -- refs are on the trap line
      trap cleanup_tmp EXIT INT TERM           # named function -- refs are in its BODY

    Harvesting only the trap LINE (the original implementation) silently returned an
    empty set for the second shape: a bare function name contains no `$` at all, so every
    `\$\{?(\w+)\}?` pattern found nothing and rule (a) had no owned array to match
    against. The named-function form is common precisely BECAUSE the cleanup is
    non-trivial -- i.e. exactly where the leak is worth catching.

    Resolving one level of indirection is deliberate: a trap naming a function that
    itself dispatches to another function is rare enough that the added false-negative
    surface is not worth the cycle-detection complexity.
    """
    owned: set[str] = set()
    funcs = find_functions(lines)

    def harvest(code: str) -> None:
        # `${#ARR[@]}` (a length reference) is a real ownership signal and is not matched
        # by the bare-name pattern below, because `#` sits between `{` and the name.
        owned.update(re.findall(r'\$\{#(\w+)\[', code))
        owned.update(re.findall(r'\$\{(\w+)\[', code))
        owned.update(re.findall(r'\$\{?(\w+)\}?', code))

    for ln in lines:
        code = strip_comment(ln)
        if not TRAP_EXIT.search(code):
            continue
        harvest(code)
        # Resolve `trap <fn> EXIT` by harvesting the named function's body. Strip the
        # `trap` keyword and the signal names, then treat any surviving bare identifier
        # that find_functions() knows as a handler.
        handler_zone = re.sub(r'\b(?:EXIT|RETURN|INT|TERM|HUP|ERR|QUIT)\b', ' ', code)
        handler_zone = re.sub(r'(?:^|;)\s*trap\b', ' ', handler_zone)
        for tok in re.findall(r'(?<![$\w.-])([A-Za-z_]\w*)', handler_zone):
            span = funcs.get(tok)
            if span is not None:
                # Harvest the handler's body, MINUS its own `local`/`declare` names.
                #
                # Without this exclusion the two widenings compound into a false positive
                # on correct code. A handler that copies the cleanup array into a local
                # (`cleanup() { local paths=("${TMP_PATHS[@]}"); rm -f "${paths[@]}"; }`)
                # would otherwise leak the name `paths` into the owned set, and any
                # UNRELATED helper with its own per-invocation `local paths=()` would be
                # flagged for appending to a "trap-owned" array it has nothing to do with.
                # A handler's locals are its private state; they can never be the parent
                # array whose registration a subshell discards.
                fstart, fend = span
                handler_locals = {
                    m.group(1)
                    for k in range(fstart, min(fend + 1, len(lines)))
                    for m in [LOCAL_DECL.search(strip_comment(lines[k]))]
                    if m
                }
                before = set(owned)
                for k in range(fstart, min(fend + 1, len(lines))):
                    harvest(strip_comment(lines[k]))
                owned.difference_update(handler_locals - before)
    return owned


def declared_local(lines: list[str], start: int, end: int, name: str) -> bool:
    """True when `name` is declared `local`/`declare` inside the function body.

    Command-position anchored, NOT line-start anchored, and applied with `.search()`.

    This must stay symmetric with ARRAY_APPEND. When ARRAY_APPEND was widened to see a
    mid-line append in a one-liner helper, this exemption was left `^\\s*`-anchored, and
    the asymmetry was a false positive on correct code: in

        collect() { local paths=(); paths+=("$1"); printf '%s' "${paths[0]}"; }

    the append was now visible but the `local` that makes it per-invocation state was
    not, so a correct helper got flagged for "appending to a trap-owned array". Any
    future widening of one of these two patterns must widen the other.
    """
    pat = re.compile(
        r'(?:^|[;&|{(]|\bthen\b|\bdo\b|\belse\b)\s*(?:local|declare|typeset)\b[^;]*?\b'
        + re.escape(name) + r'\b'
    )
    return any(pat.search(strip_comment(lines[k])) for k in range(start, min(end + 1, len(lines))))


def check_rule_a(path: Path, lines: list[str]) -> list[str]:
    """Helper appends to a TRAP-OWNED array AND is invoked via command substitution."""
    problems: list[str] = []
    funcs = find_functions(lines)
    owned = trap_owned_arrays(lines)
    for name, (start, end) in funcs.items():
        appends: list[tuple[int, str]] = []
        for k in range(start, min(end + 1, len(lines))):
            # `.search()`, not `.match()` -- ARRAY_APPEND is command-position-anchored
            # rather than line-start-anchored, so the append may legitimately begin
            # partway into a one-liner function body. `.match()` would re-impose the
            # very line-start constraint the regex was widened to drop.
            m = ARRAY_APPEND.search(strip_comment(lines[k]))
            if not m:
                continue
            arr = m.group(1)
            # Only cleanup arrays owned by a parent EXIT trap can suffer this defect.
            if arr not in owned:
                continue
            # A `local` array is per-invocation state, not shared cleanup state.
            if declared_local(lines, start, end, arr):
                continue
            appends.append((k, arr))
        if not appends:
            continue
        # Is this helper ever invoked as `$(name)` / `` `name` `` OUTSIDE its own body?
        call = re.compile(r'\$\(\s*' + re.escape(name) + r'\b[^)]*\)')
        callsites = [
            k for k in range(len(lines))
            if not (start <= k <= end) and call.search(strip_comment(lines[k]))
        ]
        if not callsites:
            continue
        for k, arr in appends:
            is_esc, err = escaped(lines, k)
            if err:
                problems.append(f"{path}:{err}")
                continue
            if is_esc:
                continue
            problems.append(
                f"{path}:{k + 1}: rule (a) subshell-append: `{arr}+=(...)` runs inside "
                f"`{name}()`, which is invoked via command substitution at line(s) "
                f"{', '.join(str(c + 1) for c in callsites[:3])}. Command substitution "
                f"runs `{name}` in a SUBSHELL, so this append mutates a copy and is lost; "
                f"the parent `{arr}` stays empty and its EXIT trap owns nothing. "
                f"Register in the PARENT scope at each call site instead (see #6734)."
            )
    return problems


def merge_base() -> str | None:
    """The merge base against the trunk, or None if it cannot be resolved.

    NOT always resolvable, and the failure is NOT hypothetical: `actions/checkout`
    defaults to `fetch-depth: 1`, so on a shallow CI checkout `origin/main` does not
    exist and `git merge-base` exits 128. This linter must also run on a developer
    clone that named its remote something other than `origin`, or has no remote at
    all. Hence: try the candidates, and let the caller decide how to degrade.
    """
    for ref in ("origin/main", "main", "origin/HEAD"):
        proc = subprocess.run(
            ["git", "merge-base", "HEAD", ref],
            cwd=REPO_ROOT, capture_output=True, text=True,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            return proc.stdout.strip()
    return None


def added_lines(path: Path) -> set[int] | None:
    """1-based line numbers ADDED to `path` vs the merge base. None = whole file is new.

    Rule (c) gates NEW ENTRANTS. An earlier implementation read that as "any file in the
    changed set", which meant touching ANY of the 122 accepted class-b files demanded you
    also pay off its pre-existing debt. That punishes incidental edits and is how a gate
    gets switched off: inngest-doublefire-probe.test.sh carries 13 allocations and zero
    traps ON origin/main, and was flagged only because this PR appended a test to it.

    So the unit is the added LINE, not the touched file.
    """
    base = merge_base()
    if base is None:
        # Fail OPEN for this rule: an unresolvable base must not invent violations.
        return set()
    try:
        rel = path.relative_to(REPO_ROOT) if path.is_relative_to(REPO_ROOT) else path
        diff = subprocess.run(
            ["git", "diff", "--no-color", "--no-ext-diff", "--unified=0", f"{base}...HEAD", "--", str(rel)],
            cwd=REPO_ROOT, capture_output=True, text=True, check=True,
        ).stdout
        if not diff.strip():
            # Untracked (never committed) => treat every line as new.
            tracked = subprocess.run(
                ["git", "ls-files", "--error-unmatch", str(rel)],
                cwd=REPO_ROOT, capture_output=True, text=True,
            ).returncode == 0
            return None if not tracked else set()
    except (subprocess.CalledProcessError, FileNotFoundError, ValueError):
        # Fail OPEN for this rule: an unresolvable diff must not invent violations.
        return set()

    out: set[int] = set()
    for m in re.finditer(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@', diff, re.M):
        start = int(m.group(1))
        count = 1 if m.group(2) is None else int(m.group(2))
        out.update(range(start, start + count))
    return out


def check_rule_c(path: Path, lines: list[str], line_scoped: bool = True) -> list[str]:
    """File calls mktemp with no owning trap, and the allocation is NEWLY ADDED.

    `line_scoped=False` lints the WHOLE file and asks git nothing. That is the right
    semantics when a caller named the path explicitly ("lint this file"), and it is
    load-bearing for the test suite: the fixtures are committed, so under line scoping
    they read as "added" only until this PR merges, after which the diff against the
    base is empty and every rule (c) positive-arm assertion silently stops firing. A
    gate whose own tests expire on merge is worse than no gate.
    """
    mk_lines = [k for k, ln in enumerate(lines) if MKTEMP.search(strip_literals(strip_comment(ln)))]
    if not mk_lines:
        return []
    if any(TRAP_EXIT.search(strip_comment(ln)) for ln in lines):
        return []
    fresh = added_lines(path) if line_scoped else None
    if fresh is not None:
        mk_lines = [k for k in mk_lines if (k + 1) in fresh]
        if not mk_lines:
            return []
    first = mk_lines[0]
    is_esc, err = escaped(lines, first)
    if err:
        return [f"{path}:{err}"]
    if is_esc:
        return []
    return [
        f"{path}:{first + 1}: rule (c) mktemp with no owning trap: this file allocates "
        f"a tempfile but registers no `trap ... EXIT`, so nothing removes it if the "
        f"script dies between allocation and cleanup. Add a single owning trap, or "
        f"annotate `# lint-trap-ownership: ok <reason>` if the leak is genuinely bounded "
        f"(see ADR-129)."
    ]


# ---------------------------------------------------------------------------------------
# Rules (d) and (e): allocations in Python / TS / JS, and hard-coded /tmp bases
# ---------------------------------------------------------------------------------------

# A literal base: the string IS /tmp or /var/tmp, or starts with it as a path component.
LITERAL_BASE_RE = re.compile(r'^/(?:var/)?tmp(?:/|$)')
# Shell form, applied to the text AFTER the `mktemp` word: a `/tmp` or `/var/tmp` that
# starts a token (preceded by start / whitespace / `=` / a quote). `${TMPDIR:-/tmp}` is
# preceded by `-` and `$BASE/tmp/x` by a word char, so neither matches -- only a base the
# author hard-coded does.
LIT_BASE_SH = re.compile(r'(?:^|[\s="\'])(?:/var)?/tmp(?:[/"\'\s)`]|$)')

# Cheap superset prefilter: a file with none of these substrings cannot allocate, so the
# (comparatively expensive) lexers never run on the other ~99% of the tree.
RAW_ALLOC_RE = re.compile(r'mkdtemp|mkstemp|mktemp|NamedTemporaryFile')

PY_ALLOC_NAMES = {"mkdtemp", "mkstemp", "mktemp"}
PY_E_NAMES = PY_ALLOC_NAMES | {"NamedTemporaryFile"}
PY_CLEAN_NAMES = {
    "rmtree", "rmdir", "removedirs", "unlink", "cleanup", "addCleanup", "addfinalizer",
    "TemporaryDirectory",
}
PY_SUBPROCESS_NAMES = {"run", "call", "check_call", "check_output", "Popen"}
PY_MARK_NAMES = {
    "ensure_scratch_session", "soleur_scratch_mark_owned", "mark_owned",
    "SOLEUR_SCRATCH_SESSION_ROOT",
}
OWNED_MARKER_PREFIX = ".soleur-owned"
SESSION_ROOT_VAR = "SOLEUR_SCRATCH_SESSION_ROOT"

TS_ALLOC = re.compile(r'\bmkdtemp(?:Sync)?\s*\(')
TS_CLEAN = re.compile(
    r'\b(?:rmSync|rmdirSync|unlinkSync|rimraf(?:Sync)?|removeSync|rm|rmdir|unlink)\s*\('
)
TS_MARK_CALL = re.compile(r'\b(?:ensureScratchSession|soleurScratchMarkOwned|markOwned)\s*\(')
TS_MARK_ID = re.compile(r'\b' + SESSION_ROOT_VAR + r'\b')
REGEX_PRECEDERS = set("(,=:[!&|?{;+-*%<>~^")
REGEX_KEYWORDS = {
    "return", "typeof", "case", "in", "of", "delete", "void", "throw", "new", "else",
    "do", "yield", "await",
}


class FloorError(Exception):
    """A walk returned nothing: 'nothing checked' must never read as 'clean'."""


class Analysis:
    """What the lexers learned about one py/ts file."""

    def __init__(self) -> None:
        self.parsed = True
        self.parse_error = ""
        self.allocs: list[tuple[int, int, str]] = []   # (line, end_line, name) -- rule (d)
        self.elits: list[tuple[int, int, str]] = []    # literal-base sites -- rule (e)
        self.cleanup = False
        self.marker = False


def lex_ts(src: str) -> tuple[str, list[tuple[int, int, str]]]:
    """Mask comments, string/template literals and regex literals out of TS/JS source.

    Returns (masked, strings). `masked` is the same length as `src` with every masked
    character replaced by a space (newlines kept), so offsets and line numbers still line
    up; `strings` lists every string literal and static template chunk as
    (start, end, raw content). Code inside a template's `${ ... }` stays visible, because
    `${mkdtempSync(...)}` is a real call.

    This is a lexer pass, not a parser: it exists so a cleanup or allocation token that
    only appears in prose or a string neither satisfies nor triggers the rule. Known
    imprecision: regex-literal-vs-division is decided from the previous token (as most
    lightweight tokenizers do), so an unusual `) /re/` shape can mis-mask one line.
    """
    n = len(src)
    out = list(src)
    strings: list[tuple[int, int, str]] = []
    last = [""]

    def blank(a: int, b: int) -> None:
        for k in range(a, min(b, n)):
            if out[k] != "\n":
                out[k] = " "

    def prev_word(i: int) -> str:
        j = i - 1
        while j >= 0 and out[j].isspace():
            j -= 1
        k = j
        while k >= 0 and (out[k].isalnum() or out[k] in "_$"):
            k -= 1
        return "".join(out[k + 1:j + 1])

    def regex_allowed(i: int) -> bool:
        lc = last[0]
        if lc == "":
            return True
        if lc in REGEX_PRECEDERS:
            return True
        if lc.isalnum() or lc in "_$":
            return prev_word(i) in REGEX_KEYWORDS
        return False

    def scan_string(i: int, q: str) -> int:
        j = i + 1
        while j < n:
            c = src[j]
            if c == "\\":
                j += 2
                continue
            if c == q or c == "\n":
                break
            j += 1
        j = min(j, n)
        end = j + 1 if j < n and src[j] == q else j
        strings.append((i, end, src[i + 1:j]))
        blank(i, end)
        return end

    def scan_regex(i: int) -> int:
        j = i + 1
        in_class = False
        while j < n:
            c = src[j]
            if c == "\n":
                return 0
            if c == "\\":
                j += 2
                continue
            if c == "[":
                in_class = True
            elif c == "]":
                in_class = False
            elif c == "/" and not in_class:
                j += 1
                while j < n and src[j].isalpha():
                    j += 1
                return j
            j += 1
        return 0

    def scan_template(i: int) -> int:
        blank(i, i + 1)
        j = i + 1
        chunk = j
        while j < n:
            c = src[j]
            if c == "\\":
                j += 2
                continue
            if c == "`":
                strings.append((chunk, j, src[chunk:j]))
                blank(chunk, j + 1)
                return j + 1
            if c == "$" and src.startswith("${", j):
                strings.append((chunk, j, src[chunk:j]))
                blank(chunk, j)
                last[0] = "("
                j = scan_code(j + 2, True) + 1
                chunk = j
                continue
            j += 1
        strings.append((chunk, n, src[chunk:n]))
        blank(chunk, n)
        return n

    def scan_code(i: int, nested: bool) -> int:
        depth = 0
        while i < n:
            c = src[i]
            if c == "/" and src.startswith("//", i):
                j = src.find("\n", i)
                j = n if j < 0 else j
                blank(i, j)
                i = j
                continue
            if c == "/" and src.startswith("/*", i):
                j = src.find("*/", i + 2)
                end = n if j < 0 else j + 2
                blank(i, end)
                i = end
                continue
            if c in "'\"":
                i = scan_string(i, c)
                last[0] = '"'
                continue
            if c == "`":
                i = scan_template(i)
                last[0] = '"'
                continue
            if c == "/" and regex_allowed(i):
                j = scan_regex(i)
                if j:
                    blank(i, j)
                    last[0] = '"'
                    i = j
                    continue
            if c == "{":
                depth += 1
            elif c == "}":
                if nested and depth == 0:
                    return i
                depth -= 1
            if not c.isspace():
                last[0] = c
            i += 1
        return i

    scan_code(0, False)
    return "".join(out), strings


def _matching_paren(masked: str, open_idx: int) -> int:
    depth = 0
    for k in range(open_idx, len(masked)):
        ch = masked[k]
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return k
    return len(masked)


def analyze_ts(text: str) -> Analysis:
    an = Analysis()
    masked, strings = lex_ts(text)

    def line_of(off: int) -> int:
        return text.count("\n", 0, off) + 1

    for m in TS_ALLOC.finditer(masked):
        ln = line_of(m.start())
        name = m.group(0).split("(")[0].strip()
        an.allocs.append((ln, ln, name))
        end = _matching_paren(masked, m.end() - 1)
        if any(m.end() <= a < end and LITERAL_BASE_RE.match(c) for a, _b, c in strings):
            an.elits.append((ln, line_of(end), name))
    an.cleanup = bool(TS_CLEAN.search(masked))
    an.marker = bool(
        TS_MARK_CALL.search(masked)
        or TS_MARK_ID.search(masked)
        or any(c.startswith(OWNED_MARKER_PREFIX) or c == SESSION_ROOT_VAR for _a, _b, c in strings)
    )
    return an


def analyze_py(text: str) -> Analysis:
    """Read a Python file through `ast`; a file `ast` cannot parse is reported UNPARSED.

    Unparsed is never a crash and never a silent pass: when the raw text contains an
    allocation token the file is treated as an allocation with no provable cleanup (RED);
    when it contains none, it cannot allocate and there is nothing to report.
    """
    import warnings

    an = Analysis()
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            tree = ast.parse(text)
    except (SyntaxError, ValueError, RecursionError, MemoryError) as exc:
        an.parsed = False
        an.parse_error = f"{type(exc).__name__}: {str(exc).splitlines()[0] if str(exc) else ''}"
        for k, ln in enumerate(text.splitlines()):
            if RAW_ALLOC_RE.search(ln):
                an.allocs.append((k + 1, k + 1, "unparsed"))
        return an

    alias: dict[str, str] = {}
    bare_strings: set[int] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom):
            for a in node.names:
                if a.asname:
                    alias[a.asname] = a.name
        elif isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant) \
                and isinstance(node.value.value, str):
            bare_strings.add(id(node.value))   # docstrings / bare prose are not code

    def call_name(node: ast.Call) -> str | None:
        f = node.func
        if isinstance(f, ast.Name):
            return alias.get(f.id, f.id)
        if isinstance(f, ast.Attribute):
            return f.attr
        return None

    def is_atexit_register(node: ast.AST) -> bool:
        return (
            isinstance(node, ast.Attribute) and node.attr == "register"
            and isinstance(node.value, ast.Name) and node.value.id == "atexit"
        )

    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            nm = call_name(node)
            end = getattr(node, "end_lineno", node.lineno) or node.lineno
            if nm in PY_ALLOC_NAMES:
                an.allocs.append((node.lineno, end, nm))
            elif nm == "NamedTemporaryFile" and any(
                kw.arg == "delete" and isinstance(kw.value, ast.Constant) and kw.value.value is False
                for kw in node.keywords
            ):
                an.allocs.append((node.lineno, end, nm))
            if nm in PY_E_NAMES:
                parts = list(node.args) + [kw.value for kw in node.keywords]
                if any(
                    isinstance(c, ast.Constant) and isinstance(c.value, str)
                    and LITERAL_BASE_RE.match(c.value)
                    for part in parts for c in ast.walk(part)
                ):
                    an.elits.append((node.lineno, end, nm))
            if nm in PY_CLEAN_NAMES:
                an.cleanup = True
            elif nm == "remove" and isinstance(node.func, ast.Attribute) \
                    and isinstance(node.func.value, ast.Name) and node.func.value.id == "os":
                an.cleanup = True
            elif nm in PY_SUBPROCESS_NAMES and any(
                isinstance(a, (ast.List, ast.Tuple)) and a.elts
                and isinstance(a.elts[0], ast.Constant) and a.elts[0].value == "rm"
                for a in node.args
            ):
                an.cleanup = True
            if nm in PY_MARK_NAMES:
                an.marker = True
        elif is_atexit_register(node):
            an.cleanup = True   # also the decorator form, which is not a Call node
        elif isinstance(node, ast.Attribute) and node.attr in PY_MARK_NAMES:
            an.marker = True
        elif isinstance(node, ast.Name) and node.id in PY_MARK_NAMES:
            an.marker = True
        elif isinstance(node, ast.Constant) and isinstance(node.value, str) \
                and id(node) not in bare_strings \
                and (node.value.startswith(OWNED_MARKER_PREFIX) or node.value == SESSION_ROOT_VAR):
            an.marker = True
    an.allocs.sort()
    an.elits.sort()
    return an


def shell_literal_base_sites(lines: list[str]) -> list[tuple[int, int, str]]:
    """Rule (e) for shell: a `mktemp` in command position with a literal /tmp|/var/tmp arg."""
    sites: list[tuple[int, int, str]] = []
    for k, ln in enumerate(lines):
        if "mktemp" not in ln:   # MKTEMP needs the literal word; skip the lexing otherwise
            continue
        sc = strip_comment(ln)
        code = strip_literals(sc)
        for m in MKTEMP.finditer(code):
            rest = re.split(r'[;&|]', sc[m.end():], maxsplit=1)[0]
            if LIT_BASE_SH.search(rest):
                sites.append((k + 1, k + 1, "mktemp"))
                break
    return sites


def lang_of(path: Path) -> str:
    """'py' | 'ts' | 'sh' from the suffix, ignoring a trailing `.fixture` (test fixtures)."""
    name = path.name
    if name.endswith(".fixture"):
        name = name[: -len(".fixture")]
    suf = Path(name).suffix
    if suf in PY_EXT:
        return "py"
    if suf in TS_EXT:
        return "ts"
    return "sh"


def is_test_shaped(rel: str, lang: str) -> bool:
    name = posixpath.basename(rel)
    dirs = rel.split("/")[:-1]
    if any(seg in ("test", "tests", "__tests__") for seg in dirs):
        return True
    if lang == "py":
        return bool(re.match(r'^(?:test_.*|.*_test|conftest)\.py$', name))
    return bool(re.search(r'\.(?:test|spec)\.(?:ts|mjs|js)$', name))


def _strip_config_comments(text: str) -> str:
    return "\n".join(
        ln for ln in text.splitlines() if not re.match(r'^\s*(?:#|//)', ln)
    )


def covered_roots(files: set[str], read) -> dict[str, list[str]]:
    """Runner session roots, derived like incident-sandbox-coverage.test.sh derives its own.

    ts: a tracked `bunfig.toml` (`preload = [...]`) or `vitest.config.ts`
        (`globalSetup: [...]`) whose declared entry file exists covers TS/JS beneath its
        directory.
    py: a tracked `conftest.py` covers Python beneath its directory.
    Directory '' is the repo root. Registration is checked, not what the entry calls --
    that assertion belongs to the coverage suite.
    """
    roots: dict[str, list[str]] = {"ts": [], "py": []}
    for rel in sorted(files):
        name = posixpath.basename(rel)
        d = posixpath.dirname(rel)
        if name == "conftest.py":
            roots["py"].append(d)
        elif name in ("bunfig.toml", "vitest.config.ts"):
            text = read(rel)
            if not text:
                continue
            for m in re.finditer(r'(?:preload|globalSetup)\s*[:=]\s*\[([^\]]*)\]', _strip_config_comments(text)):
                entries = re.findall(r'"([^"]+)"|\'([^\']+)\'', m.group(1))
                if any(posixpath.normpath(posixpath.join(d, a or b)) in files for a, b in entries):
                    roots["ts"].append(d)
                    break
    return roots


def runner_owned_test(rel: str, lang: str, roots: dict[str, list[str]]) -> bool:
    """Test-shaped AND beneath a runner session root -- never the name alone."""
    if lang not in roots or not is_test_shaped(rel, lang):
        return False
    return any(r == "" or rel.startswith(r + "/") for r in roots[lang])


def check_rule_d(path: Path, lines: list[str], an: Analysis, fresh: set[int] | None) -> list[str]:
    """Allocation in a non-test py/ts file with no cleanup construct or owner marker."""
    if not an.allocs or (an.parsed and (an.cleanup or an.marker)):
        return []
    cand = [
        a for a in an.allocs
        if fresh is None or any(ln in fresh for ln in range(a[0], a[1] + 1))
    ]
    if not cand:
        return []
    line, _end, name = cand[0]
    is_esc, err = escaped(lines, line - 1)
    if err:
        return [f"{path}:{err}"]
    if is_esc:
        return []
    if not an.parsed:
        return [
            f"{path}:{line}: rule (d) unparsed: `ast` cannot parse this file "
            f"({an.parse_error}) and its text contains an allocation token, so cleanup "
            f"cannot be proven. Fix the syntax, or annotate "
            f"`# lint-trap-ownership: ok <reason>`."
        ]
    return [
        f"{path}:{line}: rule (d) allocation with no cleanup: `{name}` creates scratch "
        f"but this file has no removal call (rmtree / rmSync / rm / TemporaryDirectory / "
        f"atexit ...) and no owner marker, so a crash or an early return leaves it behind. "
        f"Add cleanup, route it through the per-run scratch root, or annotate "
        f"`lint-trap-ownership: ok <reason>` (see #7004)."
    ]


def check_rule_e(path: Path, lines: list[str], sites: list[tuple[int, int, str]],
                 fresh: set[int] | None) -> list[str]:
    """A scratch allocation whose base is a hard-coded /tmp or /var/tmp literal."""
    problems: list[str] = []
    for line, end, name in sites:
        if fresh is not None and not any(ln in fresh for ln in range(line, end + 1)):
            continue
        is_esc, err = escaped(lines, line - 1)
        if err:
            problems.append(f"{path}:{err}")
            continue
        if is_esc:
            continue
        problems.append(
            f"{path}:{line}: rule (e) hard-coded temp base: `{name}` is given a literal "
            f"/tmp or /var/tmp base, which bypasses every per-run scratch root (no reaper "
            f"can claim it). Use the session root / `${{TMPDIR:-...}}` / `os.tmpdir()`, or "
            f"annotate `lint-trap-ownership: ok <reason>`."
        )
    return problems


# ---------------------------------------------------------------------------------------
# File sources and censuses
# ---------------------------------------------------------------------------------------

def _git(args: list[str], *, text: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=REPO_ROOT, capture_output=True, text=text)


def _in_scope(rel: str) -> bool:
    return rel.endswith(ALL_EXT) or posixpath.basename(rel) == "bunfig.toml"


class Tree:
    """A set of tracked files and their contents: the working tree, or a commit.

    One census implementation reads both, so "the census at the merge base" and "the
    census now" can never be computed by two different definitions.
    """

    def __init__(self, ref: str | None = None) -> None:
        self.ref = ref
        self._files: list[str] | None = None
        self._texts: dict[str, str] = {}

    def files(self) -> list[str]:
        if self._files is None:
            if self.ref is None:
                proc = _git(["ls-files", "-z"])
            else:
                proc = _git(["ls-tree", "-r", "-z", "--name-only", self.ref])
            if proc.returncode != 0:
                raise RuntimeError(f"git file listing failed (rc={proc.returncode}): {proc.stderr[:200]}")
            self._files = [f for f in proc.stdout.split("\0") if f and _in_scope(f)]
        return self._files

    def preload(self) -> None:
        todo = [f for f in self.files() if f not in self._texts]
        if self.ref is None:
            for f in todo:
                try:
                    self._texts[f] = (REPO_ROOT / f).read_text(encoding="utf-8", errors="replace")
                except OSError:
                    self._texts[f] = ""
            return
        proc = subprocess.run(
            ["git", "cat-file", "--batch"], cwd=REPO_ROOT, capture_output=True,
            input="".join(f"{self.ref}:{f}\n" for f in todo).encode(),
        )
        data = proc.stdout
        pos = 0
        for f in todo:
            nl = data.find(b"\n", pos)
            if nl < 0:
                break
            header = data[pos:nl].split()
            if len(header) == 3 and header[1] == b"blob":
                size = int(header[2])
                self._texts[f] = data[nl + 1:nl + 1 + size].decode("utf-8", errors="replace")
                pos = nl + 1 + size + 1
            else:
                self._texts[f] = ""
                pos = nl + 1

    def text(self, rel: str) -> str:
        if rel not in self._texts:
            self.preload()
        return self._texts.get(rel, "")


def census_all(tree: Tree) -> dict[str, int]:
    """Every counter the ratchet and the diagnostics read, from one pass over one tree.

    shell           class-b population: tracked *.sh with a mktemp and ZERO `trap ... EXIT`
                    (rule (c)'s population; unchanged definition, escape NOT honoured)
    rule-d          non-test py/ts/js files with an allocation and no cleanup / owner marker
    rule-e          files (any language) with a literal /tmp|/var/tmp allocation base
    excluded-tests  rule-d members that are runner-owned test files (counted, not gated)
    scanned-*       files walked per family -- the floors
    unparsed-py     candidate py files `ast` could not parse (they count toward rule-d)
    """
    files = tree.files()
    shell = [f for f in files if f.endswith(SHELL_E_EXT)]
    py = [f for f in files if f.endswith(PY_EXT)]
    ts = [f for f in files if f.endswith(TS_EXT)]
    for fam, got in (("shell", [f for f in shell if f.endswith(SHELL_EXT)]), ("py", py), ("ts", ts)):
        if not got:
            raise FloorError(
                f"file walk returned 0 {fam} files: a scan that saw nothing is not a "
                f"clean scan (git listing broken, wrong cwd, or the tree is empty)"
            )
    tree.preload()
    roots = covered_roots(set(files), tree.text)
    out = {
        "shell": 0, "rule-d": 0, "rule-e": 0, "excluded-tests": 0,
        "scanned-shell": len([f for f in shell if f.endswith(SHELL_EXT)]),
        "scanned-py": len(py), "scanned-ts": len(ts), "unparsed-py": 0,
    }
    for f in shell:
        lines = tree.text(f).splitlines()
        if f.endswith(SHELL_EXT):
            # `"mktemp" in ln` is a sound prefilter (MKTEMP cannot match without the word).
            has_mk = any(
                "mktemp" in ln and MKTEMP.search(strip_literals(strip_comment(ln)))
                for ln in lines
            )
            if has_mk and not any(TRAP_EXIT.search(strip_comment(ln)) for ln in lines):
                out["shell"] += 1
        if "mktemp" in tree.text(f) and shell_literal_base_sites(lines):
            out["rule-e"] += 1
    for f in py + ts:
        text = tree.text(f)
        if not RAW_ALLOC_RE.search(text):
            continue
        lang = "py" if f.endswith(PY_EXT) else "ts"
        an = analyze_py(text) if lang == "py" else analyze_ts(text)
        if not an.parsed:
            out["unparsed-py"] += 1
        if an.elits:
            out["rule-e"] += 1
        if an.allocs and not (an.parsed and (an.cleanup or an.marker)):
            if runner_owned_test(f, lang, roots):
                out["excluded-tests"] += 1
            else:
                out["rule-d"] += 1
    return out


def parse_highwater(text: str) -> dict[str, int]:
    """`79  # note` -> {'shell': 79}; `rule-d: 4  # note` -> {'rule-d': 4}."""
    got: dict[str, int] = {}
    for ln in text.splitlines():
        ln = ln.split("#")[0].strip()
        if not ln:
            continue
        m = re.match(r'^(?:([\w-]+)\s*[:=]\s*)?(\d+)$', ln)
        if m:
            got.setdefault(m.group(1) or "shell", int(m.group(2)))
    return got


def check_highwater() -> int:
    try:
        live = census_all(Tree())
    except (FloorError, RuntimeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    base = merge_base()
    if base is None:
        print(
            "warning: cannot resolve a merge base against the trunk (shallow checkout or "
            "no remote). The highwater is compared against the WORKING copy only, so a "
            "diff that edits the highwater is not cross-checked against the census delta. "
            "Fetch full history (`fetch-depth: 0`) for the real semantics.",
            file=sys.stderr,
        )

    specs = (
        ("shell", HIGHWATER_FILE, "class-b (rule (c)) population"),
        ("rule-d", TSPY_HIGHWATER_FILE, "rule (d) TS/PY population"),
        ("rule-e", TSPY_HIGHWATER_FILE, "rule (e) literal-base population"),
    )
    failed = 0
    noted: set[str] = set()
    base_census: dict[str, int] | None = None
    base_census_tried = False
    for key, hw_file, label in specs:
        if not hw_file.exists():
            print(f"error: {hw_file} missing", file=sys.stderr)
            return 2
        allowed = parse_highwater(hw_file.read_text()).get(key)
        if allowed is None:
            print(f"error: {hw_file.name} carries no `{key}` value", file=sys.stderr)
            return 2
        n = live[key]
        if n > allowed:
            what = (
                "A new file allocates a tempfile with no owning trap. Add a trap, or -- if "
                "the leak is genuinely bounded -- annotate it and raise the high-water "
                "DELIBERATELY, in the same PR, with a reason."
                if key == "shell" else
                "A new file allocates scratch with no cleanup / a hard-coded temp base. Fix "
                "it, or -- if genuinely bounded -- annotate it and raise the high-water "
                "DELIBERATELY, in the same PR, with a reason."
            )
            print(
                f"error: {label} grew to {n}, above the accepted high-water {allowed}. {what}",
                file=sys.stderr,
            )
            failed = 1
            continue
        if n < allowed:
            print(
                f"note: {label} fell to {n} (high-water {allowed}); lower "
                f"{hw_file.name} to ratchet the accept."
            )
        # Compare against the MERGE-BASE copy of the highwater, never the working copy
        # alone. A diff that edits the highwater must also move the census by exactly that
        # amount; otherwise one commit can raise the ceiling and add the entrant it
        # absorbs (or lower it for free), and the ratchet never sees either.
        if base is None:
            continue
        rel = hw_file.relative_to(REPO_ROOT).as_posix()
        shown = _git(["show", f"{base}:{rel}"])
        if shown.returncode != 0:
            if rel not in noted:
                noted.add(rel)
                print(f"note: {rel} has no merge-base copy (introduced by this diff); delta check skipped.")
            continue
        base_allowed = parse_highwater(shown.stdout).get(key)
        if base_allowed is None or base_allowed == allowed:
            continue
        if not base_census_tried:
            base_census_tried = True
            try:
                base_census = census_all(Tree(base))
            except (FloorError, RuntimeError) as exc:
                print(f"note: cannot compute the merge-base census ({exc}); delta check skipped.")
        if base_census is None:
            continue
        d_hw = allowed - base_allowed
        d_cen = n - base_census[key]
        # Snapping a lowered ceiling down to the measured population is the ratchet the
        # note above asks for; every other move must match the census delta exactly.
        if d_hw == d_cen or (d_hw < 0 and allowed == n):
            continue
        print(
            f"error: {hw_file.name} `{key}` moved {base_allowed} -> {allowed} "
            f"({d_hw:+d}) but the {label} moved {base_census[key]} -> {n} ({d_cen:+d}) vs "
            f"the merge base. A highwater edit must change the census by exactly that "
            f"amount (or snap down to the measured count).",
            file=sys.stderr,
        )
        failed = 1
    return failed


def git_changed_files() -> list[Path]:
    """Files changed vs the merge base, plus untracked ones.

    Degrades rather than aborting when the base is unresolvable (shallow checkout, no
    remote). The degraded set is untracked-only, which NARROWS rule (c) — so the
    warning below is not decoration: it is the only signal that new-entrant scoping
    ran blind. CI pins `fetch-depth: 0` on the test-scripts job precisely so the real
    semantics, not this fallback, are what gets exercised there.
    """
    base = merge_base()
    try:
        untracked = subprocess.run(
            ["git", "ls-files", "--others", "--exclude-standard"],
            cwd=REPO_ROOT, capture_output=True, text=True, check=True,
        ).stdout.split()
        if base is None:
            print(
                "warning: cannot resolve a merge base against the trunk (shallow "
                "checkout or no remote). Rule (c) new-entrant scoping is degraded to "
                "untracked files only; committed changes are NOT gated in this run. "
                "Fetch full history (`fetch-depth: 0`) for the real semantics.",
                file=sys.stderr,
            )
            out: list[str] = []
        else:
            out = subprocess.run(
                ["git", "diff", "--name-only", "--diff-filter=d", f"{base}...HEAD"],
                cwd=REPO_ROOT, capture_output=True, text=True, check=True,
            ).stdout.split()
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        print(f"error: cannot resolve changed files: {exc}", file=sys.stderr)
        sys.exit(2)
    return [REPO_ROOT / p for p in set(out) | set(untracked) if p.endswith(ALL_EXT)]


def all_tracked_files() -> list[Path]:
    try:
        files = Tree().files()
    except RuntimeError as exc:
        print(f"error: cannot list tracked files: {exc}", file=sys.stderr)
        sys.exit(2)
    return [REPO_ROOT / p for p in files if p.endswith(ALL_EXT)]


def census() -> int:
    """Count the accepted class-b population: mktemp present, zero trap ... EXIT."""
    return census_all(Tree())["shell"]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("paths", nargs="*", type=Path)
    ap.add_argument("--changed", action="store_true")
    ap.add_argument("--census", action="store_true")
    ap.add_argument("--census-tspy", action="store_true")
    ap.add_argument("--census-detail", action="store_true")
    ap.add_argument("--check-highwater", action="store_true")
    args = ap.parse_args()

    if args.census or args.census_tspy or args.census_detail:
        try:
            c = census_all(Tree())
        except (FloorError, RuntimeError) as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 2
        if args.census_detail:
            for k, v in c.items():
                print(f"{k}: {v}")
        elif args.census_tspy:
            print(c["rule-d"])
        else:
            print(c["shell"])
        return 0

    if args.check_highwater:
        return check_highwater()

    # Explicit paths mean "lint exactly this file". Asking git which of its lines are
    # new would make the answer depend on branch history rather than file content.
    line_scoped = True
    explicit = bool(args.paths)

    if args.paths:
        targets = [p if p.is_absolute() else REPO_ROOT / p for p in args.paths]
        changed_scope = set(targets)
        line_scoped = False
        if not any(p.is_file() for p in targets):
            print("error: none of the named paths is a file: nothing was checked", file=sys.stderr)
            return 2
    elif args.changed:
        targets = git_changed_files()
        changed_scope = set(targets)
    else:
        targets = all_tracked_files()
        # FLOOR: every language family must have been walked. A walk that returns zero
        # files of a family leaves that family's rules vacuously green.
        for fam, exts in (("shell", SHELL_EXT), ("python", PY_EXT), ("ts/js", TS_EXT)):
            if not any(str(p).endswith(exts) for p in targets):
                print(
                    f"error: file walk returned 0 {fam} files: nothing checked is not clean",
                    file=sys.stderr,
                )
                return 2
        # Rules (c)/(d)/(e) are ALWAYS new-entrant-scoped: the existing population is
        # accepted (ADR-129), so a full scan must not re-litigate it.
        changed_scope = set(git_changed_files())

    roots: dict[str, list[str]] | None = None

    def get_roots() -> dict[str, list[str]]:
        nonlocal roots
        if roots is None:
            try:
                t = Tree()
                roots = covered_roots(set(t.files()), t.text)
            except RuntimeError:
                roots = {"ts": [], "py": []}   # no git: no structural exclusion
        return roots

    problems: list[str] = []
    for p in sorted(set(targets)):
        if not p.is_file():
            continue
        rel = p.relative_to(REPO_ROOT) if p.is_relative_to(REPO_ROOT) else p
        lang = lang_of(p)
        run_ac = lang == "sh" and (explicit or p.suffix == ".sh")
        # Rule (a) reads every shell file; rules (c)/(d)/(e) only the in-scope ones, so
        # skip the read entirely for everything else.
        if not run_ac and p not in changed_scope:
            continue
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        lines = text.splitlines()
        if run_ac:
            problems.extend(s.replace(str(p), str(rel)) for s in check_rule_a(p, lines))
        if p not in changed_scope:
            continue
        if run_ac:
            problems.extend(
                s.replace(str(p), str(rel))
                for s in check_rule_c(p, lines, line_scoped=line_scoped)
            )
        if lang == "sh":
            sites = shell_literal_base_sites(lines) if "mktemp" in text else []
            an = None
        elif RAW_ALLOC_RE.search(text):
            an = analyze_py(text) if lang == "py" else analyze_ts(text)
            sites = an.elits
        else:
            an, sites = None, []
        if not sites and not (an and an.allocs):
            continue
        fresh = added_lines(p) if line_scoped else None
        if sites:
            problems.extend(s.replace(str(p), str(rel)) for s in check_rule_e(p, lines, sites, fresh))
        if an is not None and an.allocs:
            rel_posix = rel.as_posix() if isinstance(rel, Path) else str(rel)
            if not runner_owned_test(rel_posix, lang, get_roots()):
                problems.extend(s.replace(str(p), str(rel)) for s in check_rule_d(p, lines, an, fresh))

    for line in problems:
        print(line, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
