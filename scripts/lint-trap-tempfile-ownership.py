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

ESCAPE HATCH (mandatory -- a gate without one dies at its first false positive)
    `# lint-trap-ownership: ok <reason>`
    Must carry a non-empty reason; a bare marker is itself an error. Place it on
    the offending line or the line immediately above.

Modes:
    full-scan (default)   every tracked `*.sh`
    --changed             only files changed vs the merge base (rule (c) is
                          ALWAYS restricted to this set regardless of mode)
    --census              print the class-b population count and exit 0
    explicit paths        scan exactly those files, WHOLE-file (lefthook / test
                          harness). Rule (c) is not line-scoped here: naming a path
                          is already the scoping decision, and deferring it to git
                          history would make the fixture suite expire on merge.

Exit codes:
    0  clean
    1  one or more violations (each printed `file:line: ...` on stderr)
    2  argument or git error
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
HIGHWATER_FILE = Path(__file__).resolve().parent / "lint-trap-tempfile-ownership.highwater"

# `ARR+=( ... )` -- an append to a shell array.
ARRAY_APPEND = re.compile(r'^\s*(\w+)\+=\(')
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
ESCAPE = re.compile(r'#\s*lint-trap-ownership:\s*ok\b[ \t]*(.*)$')


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
    """Names referenced from inside a `trap ... EXIT` body.

    This is what makes rule (a) precise rather than merely suggestive. Appending to an
    array inside a `$(...)`-invoked function is only a DEFECT when the array is a
    cleanup array whose consumer -- the EXIT trap -- lives in the parent scope. Building
    a `local curl_args=()` and consuming it in the same function is the overwhelmingly
    common, entirely correct case (plugins/soleur/skills/community/scripts/discord-setup.sh,
    apps/web-platform/infra/git-data-pre-receive.test.sh). An earlier draft of this rule
    flagged those, which is precisely the "fires on correct code, disabled within a week"
    failure this gate must avoid.
    """
    owned: set[str] = set()
    for ln in lines:
        code = strip_comment(ln)
        if not TRAP_EXIT.search(code):
            continue
        owned.update(re.findall(r'\$\{(\w+)\[@\*]?', code))
        owned.update(re.findall(r'\$\{(\w+)\[', code))
        owned.update(re.findall(r'\$\{?(\w+)\}?', code))
    return owned


def declared_local(lines: list[str], start: int, end: int, name: str) -> bool:
    """True when `name` is declared `local`/`declare` inside the function body."""
    pat = re.compile(r'^\s*(?:local|declare|typeset)\b[^\n]*?\b' + re.escape(name) + r'\b')
    return any(pat.match(strip_comment(lines[k])) for k in range(start, min(end + 1, len(lines))))


def check_rule_a(path: Path, lines: list[str]) -> list[str]:
    """Helper appends to a TRAP-OWNED array AND is invoked via command substitution."""
    problems: list[str] = []
    funcs = find_functions(lines)
    owned = trap_owned_arrays(lines)
    for name, (start, end) in funcs.items():
        appends: list[tuple[int, str]] = []
        for k in range(start, min(end + 1, len(lines))):
            m = ARRAY_APPEND.match(strip_comment(lines[k]))
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
            ["git", "diff", "--unified=0", f"{base}...HEAD", "--", str(rel)],
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
    return [REPO_ROOT / p for p in set(out) | set(untracked) if p.endswith(".sh")]


def all_shell_files() -> list[Path]:
    try:
        out = subprocess.run(
            ["git", "ls-files", "*.sh"],
            cwd=REPO_ROOT, capture_output=True, text=True, check=True,
        ).stdout.split()
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        print(f"error: cannot list shell files: {exc}", file=sys.stderr)
        sys.exit(2)
    return [REPO_ROOT / p for p in out]


def census() -> int:
    """Count the accepted class-b population: mktemp present, zero trap ... EXIT."""
    n = 0
    for p in all_shell_files():
        try:
            lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        if not any(MKTEMP.search(strip_literals(strip_comment(ln))) for ln in lines):
            continue
        if not any(TRAP_EXIT.search(strip_comment(ln)) for ln in lines):
            n += 1
    return n


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("paths", nargs="*", type=Path)
    ap.add_argument("--changed", action="store_true")
    ap.add_argument("--census", action="store_true")
    ap.add_argument("--check-highwater", action="store_true")
    args = ap.parse_args()

    if args.census:
        print(census())
        return 0

    if args.check_highwater:
        live = census()
        if not HIGHWATER_FILE.exists():
            print(f"error: {HIGHWATER_FILE} missing", file=sys.stderr)
            return 2
        allowed = int(HIGHWATER_FILE.read_text().split("#")[0].strip())
        if live > allowed:
            print(
                f"error: class-b population grew to {live}, above the accepted "
                f"high-water {allowed}. A new file allocates a tempfile with no owning "
                f"trap. Add a trap, or -- if the leak is genuinely bounded -- annotate it "
                f"and raise the high-water DELIBERATELY, in the same PR, with a reason.",
                file=sys.stderr,
            )
            return 1
        if live < allowed:
            print(
                f"note: class-b population fell to {live} (high-water {allowed}); "
                f"lower {HIGHWATER_FILE.name} to ratchet the accept.",
            )
        return 0

    # Explicit paths mean "lint exactly this file". Asking git which of its lines are
    # new would make the answer depend on branch history rather than file content.
    line_scoped = True

    if args.paths:
        targets = [p if p.is_absolute() else REPO_ROOT / p for p in args.paths]
        changed_scope = set(targets)
        line_scoped = False
    elif args.changed:
        targets = git_changed_files()
        changed_scope = set(targets)
    else:
        targets = all_shell_files()
        # Rule (c) is ALWAYS new-entrant-scoped: the existing class-b population is
        # accepted (ADR-129), so a full scan must not re-litigate it.
        changed_scope = set(git_changed_files())

    problems: list[str] = []
    for p in sorted(set(targets)):
        if not p.is_file():
            continue
        try:
            lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        rel = p.relative_to(REPO_ROOT) if p.is_relative_to(REPO_ROOT) else p
        problems.extend(s.replace(str(p), str(rel)) for s in check_rule_a(p, lines))
        if p in changed_scope:
            problems.extend(
                s.replace(str(p), str(rel))
                for s in check_rule_c(p, lines, line_scoped=line_scoped)
            )

    for line in problems:
        print(line, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
